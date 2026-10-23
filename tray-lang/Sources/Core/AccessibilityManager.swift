import Foundation
import AppKit
import ApplicationServices
import Combine

/// Checks / requests Accessibility trust. Under tests uses a mock — no system prompt.
@MainActor
class AccessibilityManager: ObservableObject {
    @Published var isGranted: Bool = false

    private var checkTimer: AnyCancellable?
    private let usesMock: Bool

    init(usesMock: Bool = ProcessRuntime.useMockAccessibility) {
        self.usesMock = usesMock

        if usesMock {
            // Tests: never prompt the OS. Keep denied so we don't auto-start CGEvent taps.
            isGranted = false
            debugLog("✅ AccessibilityManager mock mode (tests) — no prompts, isGranted=false")
            return
        }

        checkStatus()
        startMonitoring()
        
    }

    func checkStatus() {
        if usesMock { return }

        let currentStatus = AXIsProcessTrusted()
        if isGranted != currentStatus {
            debugLog("🔐 Accessibility: \(currentStatus)")
            isGranted = currentStatus
        }
        updatePolling()
    }

    private var observers: [NSObjectProtocol] = []

    /// macOS posts "com.apple.accessibility.api" whenever the Accessibility list changes; the trust
    /// value lags a moment behind, so check again shortly after. Polling runs only while access is missing.
    private func startMonitoring() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { self?.checkStatus() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStatus() }
        })
        updatePolling()
    }

    private func updatePolling() {
        if isGranted {
            checkTimer = nil
        } else if checkTimer == nil {
            checkTimer = Timer.publish(every: 2.0, tolerance: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.checkStatus() }
        }
    }

    /// Shows the system prompt (macOS shows it only once per app). With `openSettings`, also opens
    /// Privacy & Security › Accessibility, which is the only way back after the prompt was dismissed.
    func requestPermissions(openSettings: Bool = false) async {
        if usesMock {
            // Explicit Grant in UI tests can flip to granted without the OS dialog.
            isGranted = true
            return
        }

        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        debugLog("🔑 Accessibility trusted: \(trusted)")

        if !trusted, openSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    deinit {
        checkTimer?.cancel()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0); NotificationCenter.default.removeObserver($0) }
    }
}
