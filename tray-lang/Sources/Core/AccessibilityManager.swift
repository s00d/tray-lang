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
    
    private var statusCheckTimer: Timer?
    private var isRequestingPermissions = false
    private var permissionAlert: NSAlert?
    
    init() {
        updateAccessibilityStatus()
        startStatusMonitoring()
    }
    
    deinit {
        statusCheckTimer?.invalidate()
    }
    
    // MARK: - Status Management
    func updateAccessibilityStatus() {
        let accessibilityEnabled = AXIsProcessTrusted()
        accessibilityStatus = accessibilityEnabled ? .granted : .denied
    }
    
    private func startStatusMonitoring() {
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAccessibilityStatus()
        }
    }
    
    private func checkAccessibilityStatus() {
        let wasGranted = accessibilityStatus == .granted
        updateAccessibilityStatus()
        
        // Если права только что были предоставлены, уведомляем об этом
        if !wasGranted && accessibilityStatus == .granted {
            print("✅ Права доступа предоставлены!")
            NotificationCenter.default.post(name: .accessibilityGranted, object: nil)
        }
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
        
        let response = alert.runModal()
        permissionAlert = nil
        isRequestingPermissions = false
        
        if response == .alertFirstButtonReturn {
            openSystemPreferences()
        } else {
            // Если пользователь отменил, обновляем статус
            updateAccessibilityStatus()
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