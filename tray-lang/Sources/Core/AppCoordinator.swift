import Foundation
import SwiftUI
import Combine

@MainActor
class AppCoordinator: ObservableObject {
    // --- UI State Properties ---
    @Published var isAutoLaunchEnabled: Bool
    @Published var isTextConversionEnabled: Bool
    @Published var isSpellCheckEnabled: Bool
    @Published var isCmdQBlockerEnabled: Bool
    @Published var isCmdWBlockerEnabled: Bool
    @Published var isAccessibilityGranted: Bool
    @Published var isSecureInputActive: Bool = false
    @Published private(set) var secureInputHolderName: String?
    @Published private(set) var isSecureInputStale: Bool = false
    @Published var isSmartLayoutEnabled: Bool
    @Published var blockerDelay: Int
    @Published private(set) var layoutHotKeyDisplay: String = ""
    @Published private(set) var spellCheckHotKeyDisplay: String = ""

    // --- Core Managers ---
    let keyboardLayoutManager: KeyboardLayoutManager
    let hotKeyManager: HotKeyManager
    let textTransformer: TextTransformer
    let spellCheckManager: SpellCheckManager
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
        self.spellCheckManager = SpellCheckManager()
        self.accessibilityManager = AccessibilityManager()
        self.autoLaunchManager = AutoLaunchManager()
        self.textProcessingManager = TextProcessingManager(
            textTransformer: textTransformer,
            keyboardLayoutManager: keyboardLayoutManager,
            spellCheckManager: spellCheckManager
        )
        self.smartLayoutManager = SmartLayoutManager(keyboardLayoutManager: keyboardLayoutManager)
        self.notificationManager = NotificationManager()
        
        // ИСПРАВЛЕНО: Инициализируем exclusionManager и hotkeyBlockerManager явно
        self.exclusionManager = ExclusionManager()
        
        // --- Первоначальная загрузка состояния из UserDefaults ---
        let savedAutoLaunch = autoLaunchManager.isAutoLaunchEnabled()
        let savedTextConversion = UserDefaults.standard.bool(forKey: DefaultsKeys.hotKeyMonitoringEnabled)
        let savedSpellCheckEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.spellCheckEnabled)
        let savedCmdQBlocker = UserDefaults.standard.bool(forKey: DefaultsKeys.qblockerEnabled)
        let savedCmdWBlocker = UserDefaults.standard.bool(forKey: DefaultsKeys.wblockerEnabled)
        
        self.isAutoLaunchEnabled = savedAutoLaunch
        self.isTextConversionEnabled = savedTextConversion
        self.isSpellCheckEnabled = savedSpellCheckEnabled
        self.isCmdQBlockerEnabled = savedCmdQBlocker
        self.isCmdWBlockerEnabled = savedCmdWBlocker
        self.isAccessibilityGranted = false // Начинаем с false, таймер исправит
        self.isSmartLayoutEnabled = false
        self.blockerDelay = 1
        
        // ИСПРАВЛЕНО: Создаем hotkeyBlockerManager с явной передачей настроек
        self.hotkeyBlockerManager = HotkeyBlockerManager(
            notificationManager: notificationManager,
            exclusionManager: exclusionManager
        )
        
        self.windowManager = WindowManager()
        
        // Явно устанавливаем начальные значения после инициализации всех свойств
        self.hotkeyBlockerManager.isCmdQEnabled = savedCmdQBlocker
        self.hotkeyBlockerManager.isCmdWEnabled = savedCmdWBlocker
        self.isSmartLayoutEnabled = smartLayoutManager.isEnabled
        self.blockerDelay = hotkeyBlockerManager.delay
        self.layoutHotKeyDisplay = hotKeyManager.layoutHotKey.displayString
        self.spellCheckHotKeyDisplay = hotKeyManager.spellCheckHotKey.displayString

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
                guard let self else { return }
                self.isAccessibilityGranted = granted
                
                if granted {
                    debugLog("✅ Права доступа получены! Перезапускаем сервисы...")
                    
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
                
                self.updateStatusBarIcon()
            }
            .store(in: &cancellables)
        
        // Эта логика связывает действия пользователя в UI с поведением менеджеров
        $isTextConversionEnabled.dropFirst()
            .receive(on: DispatchQueue.main)  // ИСПРАВЛЕНО: Обязательно в main thread!
            .sink { [weak self] enabled in
                guard let self = self else { return }
                self.hotKeyManager.saveEnabledState(enabled)
                
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                self?.isSecureInputActive = isActive
                self?.updateStatusBarIcon()
            }
            .store(in: &cancellables)

        hotKeyManager.$secureInputHolderName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.secureInputHolderName = name
            }
            .store(in: &cancellables)

        hotKeyManager.$isSecureInputStale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStale in
                self?.isSecureInputStale = isStale
            }
            .store(in: &cancellables)
            
        $isAutoLaunchEnabled.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                enabled ? self?.autoLaunchManager.enableAutoLaunch() : self?.autoLaunchManager.disableAutoLaunch()
            }
            .store(in: &cancellables)

        $isSpellCheckEnabled.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                UserDefaults.standard.set(enabled, forKey: DefaultsKeys.spellCheckEnabled)
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
        
        $isSmartLayoutEnabled.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self, self.smartLayoutManager.isEnabled != enabled else { return }
                self.smartLayoutManager.isEnabled = enabled
            }
            .store(in: &cancellables)
        
        $blockerDelay.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] delay in
                guard let self else { return }
                self.hotkeyBlockerManager.delay = delay
                self.hotkeyBlockerManager.saveSettings()
            }
            .store(in: &cancellables)
        
        hotKeyManager.$layoutHotKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hotKey in
                self?.layoutHotKeyDisplay = hotKey.displayString
            }
            .store(in: &cancellables)
        
        hotKeyManager.$spellCheckHotKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hotKey in
                self?.spellCheckHotKeyDisplay = hotKey.displayString
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .layoutHotKeyPressed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleHotKeyPressed(action: .changeLayout)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .spellCheckHotKeyPressed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.isSpellCheckEnabled else { return }
                self.handleHotKeyPressed(action: .fixSpelling)
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
    
    func stop() {
        // УЛУЧШЕНО: stateUpdateTimer больше нет, Combine сам управляет подписками
        hotKeyManager.stopMonitoring()
        hotkeyBlockerManager.stop()
        debugLog("⏹️ Приложение остановлено")
    }
    
    // MARK: - Event Handling
    private func handleHotKeyPressed(action: ProcessingAction) {
        // Проверяем права доступа
        guard isAccessibilityGranted else {
            notificationManager.showAlert(
                title: "Требуются разрешения",
                message: "Для работы приложения необходимо предоставить разрешения на доступность в настройках системы.",
                style: .warning
            )
            return
        }
        
        if action == .changeLayout {
            notificationManager.showHUD(text: "Converting layout...", icon: "🔄", delayTime: 0.5)
        } else {
            notificationManager.showHUD(text: "Fixing spelling...", icon: "✨", delayTime: 0.5)
        }
        
        // Defer processing so HUD fade-in can paint before AX/clipboard work blocks the main thread
        DispatchQueue.main.async { [weak self] in
            self?.textProcessingManager.processSelectedText(action: action)
        }
    }
    
    // MARK: - Public Interface
    func showMainWindow() {
        windowManager.showMainWindow()
    }
    
    func updateLayoutHotKey(_ newHotKey: HotKey) {
        hotKeyManager.updateLayoutHotKey(newHotKey)
        layoutHotKeyDisplay = newHotKey.displayString
    }
    
    func updateSpellCheckHotKey(_ newHotKey: HotKey) {
        hotKeyManager.updateSpellCheckHotKey(newHotKey)
        spellCheckHotKeyDisplay = newHotKey.displayString
    }

    // MARK: - Hot Key Interface
    var layoutHotKey: HotKey {
        get { hotKeyManager.layoutHotKey }
        set { updateLayoutHotKey(newValue) }
    }
    
    var spellCheckHotKey: HotKey {
        get { hotKeyManager.spellCheckHotKey }
        set { updateSpellCheckHotKey(newValue) }
    }

    func saveHotKeys() {
        hotKeyManager.saveHotKeys()
    }
    
    func stopKeyCapture() {
        hotKeyManager.stopMonitoring()
    }
    
    func startKeyCapture() {
        guard isTextConversionEnabled, isAccessibilityGranted else { return }
        hotKeyManager.startMonitoring()
    }
    
    // MARK: - Static Methods
    static func getAvailableKeyCodes() -> [KeyInfo] {
        return KeyUtils.getAvailableKeyCodes()
    }
    
    static func getAvailableModifiers() -> [(CGEventFlags, String)] {
        return KeyUtils.getAvailableModifiers()
    }
    
    func recheckSecureInput() {
        hotKeyManager.recheckSecureInput()
    }

    var secureInputStatusMessage: String {
        if isSecureInputStale {
            return "macOS session stuck after the app quit. kill won't help — lock screen (⌃⌘Q), relogin, or reboot."
        }
        if let secureInputHolderName, !secureInputHolderName.isEmpty {
            return "\(secureInputHolderName) holds Secure Input. Layout hotkeys still work; Cmd+Q/W blocker may not."
        }
        return "Another app holds Secure Input. Layout hotkeys still work; Cmd+Q/W blocker may not."
    }

    // MARK: - Status Bar Icon Updates
    private func updateStatusBarIcon() {
        windowManager.updateStatusItemIcon(
            isEnabled: isTextConversionEnabled && isAccessibilityGranted
        )
    }
}
