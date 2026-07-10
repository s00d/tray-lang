import Foundation
import AppKit
import Carbon

struct SecureInputStatus: Equatable {
    var isActive: Bool
    var holderPID: pid_t?
    var holderProcessName: String?
    var isStaleHolder: Bool
}

enum SecureInputInspector {
    static func isActive() -> Bool {
        IsSecureEventInputEnabled()
    }

    static func isProcessRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    static func parseHolderPID(from ioregOutput: String) -> pid_t? {
        let pattern = #""?kCGSSessionSecureInputPID"?\s*=\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(ioregOutput.startIndex..<ioregOutput.endIndex, in: ioregOutput)
        guard let match = regex.firstMatch(in: ioregOutput, range: range),
              let pidRange = Range(match.range(at: 1), in: ioregOutput),
              let pid = Int32(ioregOutput[pidRange]),
              pid > 0 else {
            return nil
        }

        return pid_t(pid)
    }

    static func holderPID() -> pid_t? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            #"ioreg -l -w 0 | grep -m1 -o '"kCGSSessionSecureInputPID"=[0-9]*' | grep -o '[0-9]*'"#
        ]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(raw),
            pid > 0 else {
            return nil
        }

        return pid_t(pid)
    }

    static func processName(for pid: pid_t?) -> String? {
        guard let pid, pid > 0 else { return nil }

        if let app = NSRunningApplication(processIdentifier: pid) {
            if let name = app.localizedName, !name.isEmpty {
                return name
            }
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                return bundleID
            }
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "command="]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return "PID \(pid)"
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let name = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : "PID \(pid)"
    }

    static func resolveActiveHolder() -> SecureInputStatus {
        guard let pid = holderPID() else {
            return SecureInputStatus(isActive: true, holderPID: nil, holderProcessName: nil, isStaleHolder: false)
        }

        if !isProcessRunning(pid) {
            return SecureInputStatus(
                isActive: true,
                holderPID: pid,
                holderProcessName: "PID \(pid) (already exited)",
                isStaleHolder: true
            )
        }

        return SecureInputStatus(
            isActive: true,
            holderPID: pid,
            holderProcessName: processName(for: pid),
            isStaleHolder: false
        )
    }
}

final class SecureInputMonitor {
    private(set) var status = SecureInputStatus(
        isActive: false,
        holderPID: nil,
        holderProcessName: nil,
        isStaleHolder: false
    )

    var onChange: ((SecureInputStatus) -> Void)?

    private var observerToken: UnsafeMutableRawPointer?
    private var lookupInFlight = false

    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
            self?.installObserver()
        }
    }

    func stop() {
        removeObserver()
    }

    /// Cheap check only. Runs ioreg if secure input is active and holder is still unknown.
    func refresh() {
        updateStatus(forceHolderLookup: false)
    }

    /// User-triggered: re-check and resolve holder if secure input is active.
    func recheck() {
        updateStatus(forceHolderLookup: true)
    }

    private func updateStatus(forceHolderLookup: Bool) {
        let isActive = SecureInputInspector.isActive()

        if !isActive {
            apply(SecureInputStatus(isActive: false, holderPID: nil, holderProcessName: nil, isStaleHolder: false))
            return
        }

        if status.isActive == false {
            apply(SecureInputStatus(isActive: true, holderPID: nil, holderProcessName: nil, isStaleHolder: false))
        }

        if !forceHolderLookup, status.holderProcessName != nil {
            return
        }

        lookupHolder()
    }

    private func lookupHolder() {
        guard !lookupInFlight else { return }
        lookupInFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let next = SecureInputInspector.resolveActiveHolder()

            DispatchQueue.main.async {
                guard let self else { return }
                self.lookupInFlight = false
                self.apply(next)
            }
        }
    }

    private func apply(_ next: SecureInputStatus) {
        guard next != status else { return }

        status = next
        onChange?(next)

        if next.isActive {
            if next.isStaleHolder {
                debugLog("⚠️ Secure Input завис: PID \(next.holderPID.map(String.init) ?? "?") уже не существует")
            } else {
                let holder = next.holderProcessName ?? "unknown process"
                let pidText = next.holderPID.map(String.init) ?? "?"
                debugLog("⚠️ Secure Input активен (\(holder), pid: \(pidText))")
            }
        } else {
            debugLog("✅ Secure Input деактивирован")
        }
    }

    private func installObserver() {
        guard observerToken == nil else { return }

        let center = CFNotificationCenterGetDistributedCenter()
        let token = Unmanaged.passUnretained(self).toOpaque()
        observerToken = token

        CFNotificationCenterAddObserver(
            center,
            token,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<SecureInputMonitor>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.refresh()
                }
            },
            "com.apple.CG.HID.HIDEventSecureInput" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func removeObserver() {
        guard let token = observerToken else { return }

        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDistributedCenter(),
            token,
            CFNotificationName("com.apple.CG.HID.HIDEventSecureInput" as CFString),
            nil
        )
        observerToken = nil
    }

    deinit {
        removeObserver()
    }
}
