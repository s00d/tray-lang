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
        debugLog("✅ AccessibilityManager инициализирован с реактивным мониторингом")
    }

    func checkStatus() {
        if usesMock { return }

        let currentStatus = AXIsProcessTrusted()
        if isGranted != currentStatus {
            debugLog("🔐 Accessibility Status Changed: \(isGranted) -> \(currentStatus)")
            isGranted = currentStatus
        }
    }

    private func startMonitoring() {
        checkTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkStatus()
            }
        debugLog("🔄 Мониторинг прав доступа запущен (проверка каждую секунду)")
    }

    func requestPermissions() async {
        if usesMock || ProcessRuntime.shouldSkipAccessibilityPrompt {
            debugLog("🔑 Skipping accessibility prompt (test/mock mode)")
            // Explicit Grant in UI tests can flip to granted without OS dialog.
            if usesMock {
                isGranted = true
            }
            return
        }

        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        debugLog("🔑 Запрос прав доступа: текущий статус = \(accessEnabled)")

        if !accessEnabled {
            showGoToSettingsAlert()
        }
    }

    private func showGoToSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        let appName = AppIdentity.displayName
        alert.informativeText = "\(appName) needs accessibility permissions to perform text conversion and handle hotkeys.\n\nPlease enable \(appName) in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemPreferences()
        }
    }

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
            debugLog("🔧 Открыты системные настройки (Accessibility)")
        }
    }

    deinit {
        checkTimer?.cancel()
    }
}
