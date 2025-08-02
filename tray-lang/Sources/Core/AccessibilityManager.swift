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
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateAccessibilityStatus()
        }
    }
    
    // MARK: - Permission Request
    func requestAccessibilityPermissions() {
        accessibilityStatus = .requesting
        
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if !accessibilityEnabled {
            print("⚠️ Запрашиваем разрешения на доступность...")
            
            DispatchQueue.main.async {
                self.showPermissionAlert()
            }
        } else {
            accessibilityStatus = .granted
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Разрешения на доступность"
        alert.informativeText = "Для работы горячих клавиш необходимо разрешить доступ к системе. Нажмите 'Открыть настройки' и добавьте это приложение в список разрешенных в разделе 'Доступность'."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Отмена")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemPreferences()
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