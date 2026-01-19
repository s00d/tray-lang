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
    let notificationManager: NotificationManager
    // ИСПРАВЛЕНО: Убираем lazy для предотвращения проблем с инициализацией
    let exclusionManager: ExclusionManager
    var hotkeyBlockerManager: HotkeyBlockerManager // var для binding в UI
    let windowManager: WindowManager
    
    // УЛУЧШЕНО: stateUpdateTimer удален, используется только Combine
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // --- Инициализация менеджеров в правильном порядке ---
        self.keyboardLayoutManager = KeyboardLayoutManager()
        self.hotKeyManager = HotKeyManager()
        self.textTransformer = TextTransformer()
        self.accessibilityManager = AccessibilityManager()
        self.autoLaunchManager = AutoLaunchManager()
        self.textProcessingManager = TextProcessingManager(textTransformer: textTransformer, keyboardLayoutManager: keyboardLayoutManager)
        self.smartLayoutManager = SmartLayoutManager(keyboardLayoutManager: keyboardLayoutManager)
        self.notificationManager = NotificationManager()
        
        // ИСПРАВЛЕНО: Инициализируем exclusionManager и hotkeyBlockerManager явно
        self.exclusionManager = ExclusionManager()
        
        // --- Первоначальная загрузка состояния из UserDefaults ---
        let savedAutoLaunch = autoLaunchManager.isAutoLaunchEnabled()
        let savedTextConversion = UserDefaults.standard.bool(forKey: "hotKeyMonitoringEnabled")
        let savedCmdQBlocker = UserDefaults.standard.bool(forKey: "qblocker_enabled")
        let savedCmdWBlocker = UserDefaults.standard.bool(forKey: "wblocker_enabled")
        
        self.isAutoLaunchEnabled = savedAutoLaunch
        self.isTextConversionEnabled = savedTextConversion
        self.isCmdQBlockerEnabled = savedCmdQBlocker
        self.isCmdWBlockerEnabled = savedCmdWBlocker
        self.isAccessibilityGranted = false // Начинаем с false, таймер исправит
        
        // ИСПРАВЛЕНО: Создаем hotkeyBlockerManager с явной передачей настроек
        self.hotkeyBlockerManager = HotkeyBlockerManager(
            notificationManager: notificationManager,
            exclusionManager: exclusionManager
        )
        
        self.windowManager = WindowManager()
        
        // Явно устанавливаем начальные значения после инициализации всех свойств
        self.hotkeyBlockerManager.isCmdQEnabled = savedCmdQBlocker
        self.hotkeyBlockerManager.isCmdWEnabled = savedCmdWBlocker

        // Устанавливаем связи
        windowManager.setCoordinator(self)
        
        setupBindings()
    }
    
    private func setupBindings() {
        // НОВАЯ ЛОГИКА: Связываем монитор прав доступа с сервисами
        // Это ключевое улучшение - автоматический перезапуск при получении прав!
        accessibilityManager.$isGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                guard let self = self else { return }
                
                // 1. Обновляем UI
                self.isAccessibilityGranted = granted
                
                // 2. РЕАКЦИЯ НА ИЗМЕНЕНИЕ ПРАВ
                if granted {
                    debugLog("✅ Права доступа получены! Перезапускаем сервисы...")
                    
                    // Если мониторинг должен быть включен, но стоял на паузе из-за прав — запускаем
                    if self.isTextConversionEnabled && !self.hotKeyManager.isEnabled {
                        self.hotKeyManager.startMonitoring()
                    }
                    
                    if (self.isCmdQBlockerEnabled || self.isCmdWBlockerEnabled) && !self.hotkeyBlockerManager.isMonitoring {
                        self.hotkeyBlockerManager.isCmdQEnabled = self.isCmdQBlockerEnabled
                        self.hotkeyBlockerManager.isCmdWEnabled = self.isCmdWBlockerEnabled
                        self.hotkeyBlockerManager.updateMonitoringState()
                    }
                } else {
                    debugLog("⛔️ Права доступа отозваны! Останавливаем сервисы...")
                    if self.hotKeyManager.isEnabled {
                        self.hotKeyManager.stopMonitoring()
                    }
                    if self.hotkeyBlockerManager.isMonitoring {
                        self.hotkeyBlockerManager.stop()
                    }
                }
                
                // Обновляем иконку в статус-баре
                self.updateStatusBarIcon()
            }
            .store(in: &cancellables)
        
        // Эта логика связывает действия пользователя в UI с поведением менеджеров
        $isTextConversionEnabled.dropFirst()
            .receive(on: DispatchQueue.main)  // ИСПРАВЛЕНО: Обязательно в main thread!
            .sink { [weak self] enabled in
                guard let self = self else { return }
                self.hotKeyManager.isEnabled = enabled
                self.hotKeyManager.saveEnabledState()
                
                // Запускаем/останавливаем только если есть права
                if self.isAccessibilityGranted {
                    if enabled {
                        self.hotKeyManager.startMonitoring()
                    } else {
                        self.hotKeyManager.stopMonitoring()
                    }
                }
                
                self.updateStatusBarIcon()
            }
            .store(in: &cancellables)
        
        // НОВОЕ: Подписка на изменения Secure Input
        hotKeyManager.$isSecureInputActive
            .receive(on: DispatchQueue.main)  // ИСПРАВЛЕНО: Обязательно в main thread!
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }
            .store(in: &cancellables)
            
        $isAutoLaunchEnabled.dropFirst()
            .receive(on: DispatchQueue.main)  // ИСПРАВЛЕНО: Обязательно в main thread!
            .sink { [weak self] enabled in
                enabled ? self?.autoLaunchManager.enableAutoLaunch() : self?.autoLaunchManager.disableAutoLaunch()
            }
            .store(in: &cancellables)
            
        $isCmdQBlockerEnabled.dropFirst()
            .receive(on: DispatchQueue.main)  // ИСПРАВЛЕНО: Обязательно в main thread!
            .sink { [weak self] enabled in
                self?.hotkeyBlockerManager.isCmdQEnabled = enabled
                self?.hotkeyBlockerManager.updateMonitoringState()
            }
            .store(in: &cancellables)
            
        $isCmdWBlockerEnabled.dropFirst()
            .receive(on: DispatchQueue.main)  // ИСПРАВЛЕНО: Обязательно в main thread!
            .sink { [weak self] enabled in
                self?.hotkeyBlockerManager.isCmdWEnabled = enabled
                self?.hotkeyBlockerManager.updateMonitoringState()
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
        debugLog("🚀 Приложение запущено")
        textTransformer.loadProfiles()
        
        // УЛУЧШЕНО: Таймер-костыль удален! AccessibilityManager теперь сам мониторит через Combine
        // Запускаем первую проверку с небольшой задержкой для инициализации UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Если прав нет, запрашиваем их
            if !self.isAccessibilityGranted {
                Task {
                    await self.accessibilityManager.requestPermissions()
                }
            }
        }
    }
    
    // УДАЛЕНО: updateUIState() и updateServicesBasedOnPermissions()
    // Теперь вся логика обрабатывается через Combine subscriptions в setupBindings()
    
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
        // УЛУЧШЕНО: stateUpdateTimer больше нет, Combine сам управляет подписками
        hotKeyManager.stopMonitoring()
        hotkeyBlockerManager.stop()
        debugLog("⏹️ Приложение остановлено")
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
    
    // MARK: - Status Bar Icon Updates
    private func updateStatusBarIcon() {
        windowManager.updateStatusItemIcon(
            isSecureInputActive: hotKeyManager.isSecureInputActive,
            isEnabled: isTextConversionEnabled && isAccessibilityGranted
        )
    }
}
