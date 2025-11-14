import Foundation
import AppKit
import ApplicationServices

class AccessibilityManager {
    init() {
        // Подписываемся на системные уведомления для более быстрой реакции
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(checkStatusAndNotify),
            name: NSNotification.Name("com.apple.accessibility.api.user-settings-changed"),
            object: nil
        )
    }
    
    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }

    func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    @MainActor
    func requestPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    @objc private func checkStatusAndNotify() {
        // Просто отправляем уведомление, чтобы AppCoordinator мог среагировать
        NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
    }
}

extension Notification.Name {
    static let accessibilityStatusChanged = Notification.Name("accessibilityStatusChanged")
    static let accessibilityGranted = Notification.Name("accessibilityGranted") // Оставляем для обратной совместимости
}
