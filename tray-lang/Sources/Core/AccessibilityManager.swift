import Foundation
import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Accessibility Status
enum AccessibilityStatus {
    case unknown
    case granted
    case denied
    case requesting
    
    var description: String {
        switch self {
        case .unknown:
            return "Статус неизвестен"
        case .granted:
            return "Разрешения предоставлены"
        case .denied:
            return "Разрешения не предоставлены"
        case .requesting:
            return "Запрос разрешений..."
        }
    }
    
    var color: Color {
        switch self {
        case .unknown:
            return .orange
        case .granted:
            return .green
        case .denied:
            return .red
        case .requesting:
            return .blue
        }
    }
}

// MARK: - Accessibility Manager
class AccessibilityManager: ObservableObject {
    @Published var accessibilityStatus: AccessibilityStatus = .unknown
    
    private var isRequestingPermissions = false
    private var permissionAlert: NSAlert?
    
    init() {
        // Выполняем первую проверку с небольшой задержкой
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateAccessibilityStatus()
        }
        setupStatusMonitoring()
    }
    
    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Status Management
    @objc func updateAccessibilityStatus() {
        let wasGranted = accessibilityStatus == .granted
        let isNowTrusted = AXIsProcessTrusted()
        
        accessibilityStatus = isNowTrusted ? .granted : .denied
        
        // Если права только что были предоставлены, отправляем уведомление
        if !wasGranted && isNowTrusted {
            print("✅ Права доступа предоставлены! Отправляем уведомление.")
            NotificationCenter.default.post(name: .accessibilityGranted, object: nil)
        }
    }
    
    private func setupStatusMonitoring() {
        // Самый надежный способ: слушать системное уведомление.
        // Оно срабатывает, когда пользователь меняет галочку в настройках.
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(updateAccessibilityStatus),
            name: NSNotification.Name("com.apple.accessibility.api.user-settings-changed"),
            object: nil
        )
    }
    
    // MARK: - Permission Request
    func requestAccessibilityPermissions() {
        // Проверяем, не запрашиваем ли уже права
        guard !isRequestingPermissions else {
            print("⚠️ Запрос прав уже выполняется")
            return
        }
        
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if accessibilityEnabled {
            accessibilityStatus = .granted
            return
        }
        
        isRequestingPermissions = true
        accessibilityStatus = .requesting
        
        print("⚠️ Запрашиваем разрешения на доступность...")
        
        DispatchQueue.main.async {
            self.showPermissionAlert()
        }
    }
    
    private func showPermissionAlert() {
        // Закрываем предыдущий алерт если он открыт
        if let existingAlert = permissionAlert {
            existingAlert.window.close()
        }
        
        let alert = NSAlert()
        alert.messageText = "Разрешения на доступность"
        alert.informativeText = "Для работы горячих клавиш необходимо разрешить доступ к системе. Нажмите 'Открыть настройки' и добавьте это приложение в список разрешенных в разделе 'Доступность'."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Отмена")
        
        permissionAlert = alert
        
        // Используем асинхронный показ алерта чтобы не блокировать UI
        DispatchQueue.main.async {
            let response = alert.runModal()
            self.permissionAlert = nil
            self.isRequestingPermissions = false
            
            if response == .alertFirstButtonReturn {
                self.openSystemPreferences()
            } else {
                // Если пользователь отменил, обновляем статус
                self.updateAccessibilityStatus()
            }
        }
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Validation
    func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let accessibilityGranted = Notification.Name("accessibilityGranted")
}
