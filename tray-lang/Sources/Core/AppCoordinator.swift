import Foundation
import SwiftUI
import Combine

@MainActor
class AppCoordinator: ObservableObject {
    // --- UI State Properties ---
    @Published var isAutoLaunchEnabled: Bool
    @Published var isTextConversionEnabled: Bool
    @Published var isCmdQBlockerEnabled: Bool
    @Published var isCmdWBlockerEnabled: Bool
    @Published var isAccessibilityGranted: Bool

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
    
    private var uiUpdateTimer: Timer?
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
        
        // --- Первоначальная инициализация состояния ---
        self.isAutoLaunchEnabled = autoLaunchManager.isAutoLaunchEnabled()
        self.isTextConversionEnabled = UserDefaults.standard.bool(forKey: "hotKeyMonitoringEnabled")
        self.isCmdQBlockerEnabled = UserDefaults.standard.bool(forKey: "qblocker_enabled")
        self.isCmdWBlockerEnabled = UserDefaults.standard.bool(forKey: "wblocker_enabled")
        self.isAccessibilityGranted = false // Начинаем с false, таймер исправит

        // Устанавливаем связи
        windowManager.setCoordinator(self)
        
        setupBindings()
        setupConnections()
    }
    
    private func setupBindings() {
        // Эта логика связывает действия пользователя в UI с поведением менеджеров
        $isTextConversionEnabled.dropFirst().sink { [weak self] enabled in
            guard let self = self else { return }
            self.hotKeyManager.isEnabled = enabled
            self.hotKeyManager.saveEnabledState()
            self.updateServicesBasedOnPermissions()
        }.store(in: &cancellables)
            
        $isAutoLaunchEnabled.dropFirst().sink { [weak self] enabled in
            enabled ? self?.autoLaunchManager.enableAutoLaunch() : self?.autoLaunchManager.disableAutoLaunch()
        }.store(in: &cancellables)
            
        $isCmdQBlockerEnabled.dropFirst().sink { [weak self] enabled in
            self?.hotkeyBlockerManager.isCmdQEnabled = enabled
            self?.hotkeyBlockerManager.updateMonitoringState()
        }.store(in: &cancellables)
            
        $isCmdWBlockerEnabled.dropFirst().sink { [weak self] enabled in
            self?.hotkeyBlockerManager.isCmdWEnabled = enabled
            self?.hotkeyBlockerManager.updateMonitoringState()
        }.store(in: &cancellables)
    }
    
    private func setupConnections() {
        // Слушаем уведомление от AccessibilityManager
        NotificationCenter.default.publisher(for: .accessibilityStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUIState() // Принудительно обновляем все состояние
            }
            .store(in: &cancellables)
        
        // Слушаем нажатие горячей клавиши
        NotificationCenter.default.publisher(for: .hotKeyPressed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleHotKeyPressed()
            }
            .store(in: &cancellables)
    }
    
    func start() {
        print("🚀 Приложение запущено")
        textTransformer.loadProfiles()
        
        // Запускаем таймер, который будет поддерживать UI в актуальном состоянии
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUIState()
        }
        
        // Первый запуск с задержкой, чтобы избежать "гонки состояний"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateUIState()
            // Запрашиваем права, только если их точно нет
            if !self.isAccessibilityGranted {
                self.accessibilityManager.requestPermissions()
            }
        }
    }
    
    // --- ЦЕНТРАЛЬНЫЙ МЕТОД ОБНОВЛЕНИЯ UI ---
    @objc private func updateUIState() {
        let actualGranted = accessibilityManager.isAccessibilityGranted()
        if self.isAccessibilityGranted != actualGranted {
            self.isAccessibilityGranted = actualGranted
        }
        
        // Обновляем сервисы, если статус прав изменился
        updateServicesBasedOnPermissions()
    }
    
    // Включает/выключает сервисы в зависимости от прав и настроек
    private func updateServicesBasedOnPermissions() {
        if isAccessibilityGranted {
            if isTextConversionEnabled && !hotKeyManager.isEnabled {
                hotKeyManager.startMonitoring()
            }
            if (isCmdQBlockerEnabled || isCmdWBlockerEnabled) && !hotkeyBlockerManager.isMonitoring {
                startHotkeyBlocker()
            }
        } else {
            // Если прав нет, принудительно все выключаем
            if hotKeyManager.isEnabled {
                hotKeyManager.stopMonitoring()
            }
            if hotkeyBlockerManager.isMonitoring {
                hotkeyBlockerManager.stop()
            }
        }
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
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
        hotKeyManager.stopMonitoring()
        hotkeyBlockerManager.stop()
        print("⏹️ Приложение остановлено")
    }
    
    // MARK: - Event Handling
    private func handleHotKeyPressed() {
        // Проверяем права доступа
        guard isAccessibilityGranted else {
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
    
    func handleAccessibilityGranted() {
        print("🔄 Права доступа есть. Запускаем сервисы...")
        
        if isTextConversionEnabled {
            hotKeyManager.startMonitoring()
        }
        if isCmdQBlockerEnabled || isCmdWBlockerEnabled {
            hotkeyBlockerManager.isCmdQEnabled = isCmdQBlockerEnabled
            hotkeyBlockerManager.isCmdWEnabled = isCmdWBlockerEnabled
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
