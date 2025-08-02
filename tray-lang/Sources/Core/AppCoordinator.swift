import Foundation
import SwiftUI

// MARK: - App Coordinator
class AppCoordinator: ObservableObject {
    // Core Managers
    let keyboardLayoutManager: KeyboardLayoutManager
    let hotKeyManager: HotKeyManager
    let textTransformer: TextTransformer
    let accessibilityManager: AccessibilityManager
    
    // Processing Managers
    let textProcessingManager: TextProcessingManager
    let autoLaunchManager: AutoLaunchManager
    
    // UI Components
    let notificationManager: NotificationManager
    let windowManager: WindowManager
    
    init() {
        // Инициализируем core managers
        keyboardLayoutManager = KeyboardLayoutManager()
        hotKeyManager = HotKeyManager()
        textTransformer = TextTransformer()
        accessibilityManager = AccessibilityManager()
        
        // Инициализируем processing managers
        textProcessingManager = TextProcessingManager(textTransformer: textTransformer)
        autoLaunchManager = AutoLaunchManager()
        
        // Инициализируем UI components
        notificationManager = NotificationManager()
        windowManager = WindowManager()
        
        // Устанавливаем связи
        windowManager.setCoordinator(self)
        
        // Настраиваем связи
        setupConnections()
    }
    
    // MARK: - Setup
    private func setupConnections() {
        // Слушаем нажатие горячей клавиши
        NotificationCenter.default.addObserver(
            forName: .hotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleHotKeyPressed()
        }
    }
    
    // MARK: - App Lifecycle
    func start() {
        print("🚀 Приложение запущено")
        
        // Запрашиваем права доступа
        accessibilityManager.requestAccessibilityPermissions()
        
        // Запускаем мониторинг горячих клавиш
        hotKeyManager.startMonitoring()
        
        // Загружаем пользовательские символы
        textTransformer.loadSymbols()
    }
    
    func stop() {
        hotKeyManager.stopMonitoring()
        print("⏹️ Приложение остановлено")
    }
    
    // MARK: - Event Handling
    private func handleHotKeyPressed() {
        // Проверяем права доступа
        guard accessibilityManager.isAccessibilityGranted() else {
            notificationManager.showAlert(
                title: "Требуются разрешения",
                message: "Для работы приложения необходимо предоставить разрешения на доступность в настройках системы.",
                style: .warning
            )
            return
        }
        
        // Показываем уведомление о конвертации
        notificationManager.showConversionNotification()
        
        // Обрабатываем выделенный текст
        textProcessingManager.processSelectedText()
    }
    
    // MARK: - Public Interface
    func showMainWindow() {
        windowManager.showMainWindow()
    }
    
    func hideDockIcon() {
        windowManager.hideDockIcon()
    }
    
    func showDockIcon() {
        windowManager.showDockIcon()
    }
    
    // MARK: - Hot Key Interface
    var hotKey: HotKey {
        get { hotKeyManager.hotKey }
        set { hotKeyManager.updateHotKey(newValue) }
    }
    
    func saveHotKey() {
        hotKeyManager.saveHotKey()
    }
    
    func stopKeyCapture() {
        hotKeyManager.stopMonitoring()
    }
    
    func startKeyCapture() {
        hotKeyManager.startMonitoring()
    }
    
    // MARK: - Static Methods
    static func getAvailableKeyCodes() -> [KeyInfo] {
        return KeyUtils.getAvailableKeyCodes()
    }
    
    static func getAvailableModifiers() -> [(CGEventFlags, String)] {
        return KeyUtils.getAvailableModifiers()
    }
} 