import Foundation
import AppKit
import Carbon
import IOKit

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

    static let holderKey = "kCGSSessionSecureInputPID"

    /// PID from a session dictionary (`CGSessionCopyCurrentDictionary` or an `IOConsoleUsers` entry).
    static func holderPID(in session: [String: Any]) -> pid_t? {
        guard let value = session[holderKey] as? NSNumber, value.int32Value > 0 else { return nil }
        return pid_t(value.int32Value)
    }

    /// Same data `ioreg` prints, read in-process: no shell, no IORegistry dump.
    static func holderPID() -> pid_t? {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any], let pid = holderPID(in: session) {
            return pid
        }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        return users.lazy.compactMap(holderPID(in:)).first
    }

    static func processName(for pid: pid_t?) -> String? {
        guard let pid, pid > 0 else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid),
           let name = app.localizedName ?? app.bundleIdentifier, !name.isEmpty {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : "PID \(pid)"
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
                debugLog("⚠️ Secure Input stuck: PID \(next.holderPID.map(String.init) ?? "?") has exited")
            } else {
                let holder = next.holderProcessName ?? "unknown process"
                let pidText = next.holderPID.map(String.init) ?? "?"
                debugLog("⚠️ Secure Input on (\(holder), pid: \(pidText))")
            }
        } else {
            debugLog("✅ Secure Input off")
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
