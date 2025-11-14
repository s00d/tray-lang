import Foundation
import SwiftUI
import Combine

// MARK: - App Coordinator
class AppCoordinator: ObservableObject {
    // --- UI State Properties ---
    // Эти свойства - ЕДИНСТВЕННЫЙ источник правды для всего UI
    @Published var isAutoLaunchEnabled: Bool
    @Published var isTextConversionEnabled: Bool
    @Published var isCmdQBlockerEnabled: Bool
    @Published var isCmdWBlockerEnabled: Bool
    
    // --- Core Managers ---
    let keyboardLayoutManager: KeyboardLayoutManager
    let hotKeyManager: HotKeyManager
    let textTransformer: TextTransformer
    let accessibilityManager: AccessibilityManager
    let autoLaunchManager: AutoLaunchManager
    let textProcessingManager: TextProcessingManager
    var smartLayoutManager: SmartLayoutManager
    var hotkeyBlockerManager: HotkeyBlockerManager
    let exclusionManager: ExclusionManager
    let notificationManager: NotificationManager
    let windowManager: WindowManager
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // --- Инициализация менеджеров ---
        self.keyboardLayoutManager = KeyboardLayoutManager()
        self.hotKeyManager = HotKeyManager()
        self.textTransformer = TextTransformer()
        self.accessibilityManager = AccessibilityManager()
        self.autoLaunchManager = AutoLaunchManager()
        self.textProcessingManager = TextProcessingManager(textTransformer: textTransformer, keyboardLayoutManager: keyboardLayoutManager)
        self.smartLayoutManager = SmartLayoutManager(keyboardLayoutManager: keyboardLayoutManager)
        self.notificationManager = NotificationManager()
        self.exclusionManager = ExclusionManager()
        self.hotkeyBlockerManager = HotkeyBlockerManager(notificationManager: notificationManager, exclusionManager: exclusionManager)
        self.windowManager = WindowManager()
        
        // --- Инициализация состояния UI из UserDefaults ---
        self.isAutoLaunchEnabled = autoLaunchManager.isAutoLaunchEnabled()
        self.isTextConversionEnabled = UserDefaults.standard.bool(forKey: "hotKeyMonitoringEnabled")
        self.isCmdQBlockerEnabled = UserDefaults.standard.bool(forKey: "qblocker_enabled")
        self.isCmdWBlockerEnabled = UserDefaults.standard.bool(forKey: "wblocker_enabled")

        // Устанавливаем связи
        windowManager.setCoordinator(self)
        
        // Настраиваем реактивные связи
        setupBindings()
        setupConnections()
    }
    
    private func setupBindings() {
        // Синхронизируем состояние UI с поведением менеджеров
        
        // 1. Text Conversion
        $isTextConversionEnabled
            .dropFirst() // Пропускаем начальное значение
            .sink { [weak self] enabled in
                guard let self = self else { return }
                self.hotKeyManager.isEnabled = enabled
                self.hotKeyManager.saveEnabledState() // Сохраняем состояние
                if enabled {
                    self.hotKeyManager.startMonitoring()
                } else {
                    self.hotKeyManager.stopMonitoring()
                }
            }
            .store(in: &cancellables)
            
        // 2. Auto Launch
        $isAutoLaunchEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.autoLaunchManager.enableAutoLaunch()
                } else {
                    self?.autoLaunchManager.disableAutoLaunch()
                }
            }
            .store(in: &cancellables)
            
        // 3. Cmd+Q Blocker
        $isCmdQBlockerEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.hotkeyBlockerManager.isCmdQEnabled = enabled
                self?.hotkeyBlockerManager.updateMonitoringState()
            }
            .store(in: &cancellables)
            
        // 4. Cmd+W Blocker
        $isCmdWBlockerEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.hotkeyBlockerManager.isCmdWEnabled = enabled
                self?.hotkeyBlockerManager.updateMonitoringState()
            }
            .store(in: &cancellables)
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
        
        // Запрашиваем права, если их нет
        #if !DEBUG
        if !accessibilityManager.isAccessibilityGranted() {
            accessibilityManager.requestAccessibilityPermissions()
        }
        #else
        // В режиме разработки просто устанавливаем статус как granted
        accessibilityManager.accessibilityStatus = .granted
        print("🔧 Режим разработки: права доступа установлены автоматически")
        #endif
        
        // Сразу активируем функции, которые были включены
        if accessibilityManager.isAccessibilityGranted() {
            if isTextConversionEnabled {
                hotKeyManager.startMonitoring()
            }
            if isCmdQBlockerEnabled || isCmdWBlockerEnabled {
                startHotkeyBlocker()
            }
        }
        
        // Синхронизируем состояние HotkeyBlocker
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hotkeyBlockerManager.syncState()
        }
        
        // Загружаем пользовательские символы
        textTransformer.loadSymbols()
    }
    
    private func startHotkeyBlocker() {
        do {
            try hotkeyBlockerManager.startIfEnabled()
        } catch QBlockerError.AccessibilityPermissionDenied {
            print("❌ HotkeyBlocker: Accessibility permissions denied - HotkeyBlocker cannot start")
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "HotkeyBlocker requires accessibility permissions to monitor Cmd+Q and Cmd+W. Please enable accessibility access in System Preferences > Security & Privacy > Privacy > Accessibility.",
                style: .warning
            )
            openSystemPreferences()
        } catch QBlockerError.EventTapCreationFailed {
            print("❌ HotkeyBlocker: Failed to create event tap")
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "Failed to create event monitoring for HotkeyBlocker. This may be due to system restrictions.",
                style: .warning
            )
        } catch QBlockerError.RunLoopSourceCreationFailed {
            print("❌ HotkeyBlocker: Failed to create run loop source")
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "Failed to initialize HotkeyBlocker monitoring. Please try restarting the application.",
                style: .warning
            )
        } catch {
            print("❌ HotkeyBlocker: Unknown error: \(error)")
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "An unexpected error occurred while starting HotkeyBlocker: \(error.localizedDescription)",
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
        hotkeyBlockerManager.stop()
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
        if isTextConversionEnabled {
            hotKeyManager.startMonitoring()
        }
        if isCmdQBlockerEnabled || isCmdWBlockerEnabled {
            startHotkeyBlocker()
        }
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
