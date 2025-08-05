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
    
    // QBlocker Manager
    var qBlockerManager: QBlockerManager
    
    // Exclusion Manager
    let exclusionManager: ExclusionManager
    
    init() {
        // Инициализируем core managers
        keyboardLayoutManager = KeyboardLayoutManager()
        hotKeyManager = HotKeyManager()
        textTransformer = TextTransformer()
        accessibilityManager = AccessibilityManager()
        
        // Инициализируем processing managers
        textProcessingManager = TextProcessingManager(textTransformer: textTransformer, keyboardLayoutManager: keyboardLayoutManager)
        autoLaunchManager = AutoLaunchManager()
        
        // Инициализируем UI components
        notificationManager = NotificationManager()
        windowManager = WindowManager()
        
        // Инициализируем exclusion manager
        exclusionManager = ExclusionManager()
        
        // Инициализируем QBlocker manager
        qBlockerManager = QBlockerManager(notificationManager: notificationManager, exclusionManager: exclusionManager)
        
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
        
        // Слушаем предоставление прав доступа
        NotificationCenter.default.addObserver(
            forName: .accessibilityGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAccessibilityGranted()
        }
    }
    
    // MARK: - App Lifecycle
    func start() {
        print("🚀 Приложение запущено")
        
        // Запрашиваем права доступа
        accessibilityManager.requestAccessibilityPermissions()
        
        // Запускаем мониторинг горячих клавиш только если права уже предоставлены
        if accessibilityManager.isAccessibilityGranted() {
            hotKeyManager.startMonitoring()
        }
        
        // Запускаем QBlocker если права предоставлены и он был включен
        if accessibilityManager.isAccessibilityGranted() {
            startQBlocker()
        }
        
        // Загружаем пользовательские символы
        textTransformer.loadSymbols()
    }
    
    private func startQBlocker() {
        do {
            try qBlockerManager.startIfEnabled()
        } catch QBlockerError.AccessibilityPermissionDenied {
            print("❌ QBlocker: Accessibility permissions denied - QBlocker cannot start")
            notificationManager.showAlert(
                title: "QBlocker Error",
                message: "QBlocker requires accessibility permissions to monitor Cmd+Q. Please enable accessibility access in System Preferences > Security & Privacy > Privacy > Accessibility.",
                style: .warning
            )
            openSystemPreferences()
        } catch QBlockerError.EventTapCreationFailed {
            print("❌ QBlocker: Failed to create event tap")
            notificationManager.showAlert(
                title: "QBlocker Error",
                message: "Failed to create event monitoring for QBlocker. This may be due to system restrictions.",
                style: .warning
            )
        } catch QBlockerError.RunLoopSourceCreationFailed {
            print("❌ QBlocker: Failed to create run loop source")
            notificationManager.showAlert(
                title: "QBlocker Error",
                message: "Failed to initialize QBlocker monitoring. Please try restarting the application.",
                style: .warning
            )
        } catch {
            print("❌ QBlocker: Unknown error: \(error)")
            notificationManager.showAlert(
                title: "QBlocker Error",
                message: "An unexpected error occurred while starting QBlocker: \(error.localizedDescription)",
                style: .warning
            )
        }
    }
    
    private func openSystemPreferences() {
        let script = """
        tell application "System Preferences"
            activate
            set current pane to pane id "com.apple.preference.security"
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        do {
            try task.run()
        } catch {
            print("❌ Failed to open System Preferences: \(error)")
        }
    }
    
    func stop() {
        hotKeyManager.stopMonitoring()
        qBlockerManager.stop()
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
    
    private func handleAccessibilityGranted() {
        print("🔄 Права доступа предоставлены, запускаем мониторинг...")
        hotKeyManager.startMonitoring()
        startQBlocker()
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