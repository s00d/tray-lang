import Foundation
import AppKit
import ApplicationServices
import Combine

/// УЛУЧШЕННЫЙ AccessibilityManager с реактивным мониторингом
/// Использует Combine для автоматического обновления состояния прав доступа
@MainActor
class AccessibilityManager: ObservableObject {
    // НОВОЕ: Это свойство "живое". UI автоматически подпишется и обновится
    @Published var isGranted: Bool = false
    
    private var checkTimer: AnyCancellable?
    
    init() {
        // 1. Первая проверка при запуске
        checkStatus()
        
        // 2. Запускаем "сердцебиение" (Polling)
        // Проверяем статус каждую секунду. Это ничтожная нагрузка на CPU (<0.01%)
        startMonitoring()
        
        debugLog("✅ AccessibilityManager инициализирован с реактивным мониторингом")
    }
    
    /// Принудительная разовая проверка статуса
    func checkStatus() {
        let currentStatus = AXIsProcessTrusted()
        if isGranted != currentStatus {
            debugLog("🔐 Accessibility Status Changed: \(isGranted) -> \(currentStatus)")
            isGranted = currentStatus
        }
    }
    
    /// Запуск постоянного мониторинга через Combine Timer
    private func startMonitoring() {
        checkTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkStatus()
            }
        
        debugLog("🔄 Мониторинг прав доступа запущен (проверка каждую секунду)")
    }
    
    /// Запрос прав доступа (открытие системного диалога)
    func requestPermissions() async {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        debugLog("🔑 Запрос прав доступа: текущий статус = \(accessEnabled)")
        
        if !accessEnabled {
            // Если диалог не появился (например, права уже отклонены),
            // показываем инструкцию и открываем настройки
            showGoToSettingsAlert()
        }
    }
    
    private func showGoToSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "Tray Lang needs accessibility permissions to perform text conversion and handle hotkeys.\n\nPlease enable Tray Lang in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemPreferences()
        }
    }
    
    private func openSystemPreferences() {
        // Открываем страницу Accessibility в System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
            debugLog("🔧 Открыты системные настройки (Accessibility)")
        }
    }
    
    deinit {
        checkTimer?.cancel()
        debugLog("⏹️ AccessibilityManager деинициализирован")
    }
}
