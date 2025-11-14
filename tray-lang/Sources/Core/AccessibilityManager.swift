import Foundation
import AppKit
import ApplicationServices

class AccessibilityManager {
    
    /// Просто проверяет текущий системный статус.
    func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Запускает процесс запроса прав или открывает Настройки.
    @MainActor
    func requestPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        // Этот вызов либо покажет системный диалог, либо вернет текущий статус.
        // Если права уже были отклонены, он ничего не покажет.
        if !AXIsProcessTrustedWithOptions(options) {
            // Если диалог не был показан (потому что права уже отклонены),
            // вручную открываем настройки.
            showGoToSettingsAlert()
        }
    }
    
    @MainActor
    private func showGoToSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = "Требуются разрешения на доступность"
        alert.informativeText = "Tray Lang нуждается в разрешениях для управления текстом. Пожалуйста, включите их в Системных Настройках."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть Системные Настройки")
        alert.addButton(withTitle: "Позже")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
