import Foundation
import SwiftUI
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - UI state
    @Published var isAutoLaunchEnabled: Bool
    @Published private(set) var autoLaunchError: String?
    @Published var isTextConversionEnabled: Bool
    @Published var isSpellCheckEnabled: Bool
    @Published var isAutoConvertEnabled: Bool
    @Published var isAutoConvertSoundEnabled: Bool
    @Published var isAutoConvertSkippingCodeApps: Bool
    @Published var isCmdQBlockerEnabled: Bool
    @Published var isCmdWBlockerEnabled: Bool
    @Published var blockerDelay: Int
    @Published private(set) var isAccessibilityGranted = false
    @Published private(set) var isSecureInputActive = false
    @Published private(set) var secureInputHolderName: String?
    @Published private(set) var isSecureInputStale = false
    @Published private(set) var layoutHotKeyDisplay = ""
    @Published private(set) var spellCheckHotKeyDisplay = ""

    // MARK: - Managers
    let keyboardLayoutManager: KeyboardLayoutManager
    let hotKeyManager: HotKeyManager
    let textTransformer: TextTransformer
    let spellCheckManager: SpellCheckManager
    let accessibilityManager: AccessibilityManager
    let autoLaunchManager: AutoLaunchManager
    let notificationManager: NotificationManager
    let textProcessingManager: TextProcessingManager
    let smartLayoutManager: SmartLayoutManager
    let exclusionManager: ExclusionManager
    let hotkeyBlockerManager: HotkeyBlockerManager
    let autoConvertManager: AutoConvertManager
    let windowManager: WindowManager

    private var cancellables = Set<AnyCancellable>()

    init(selectionDriver: SelectionDriver = SystemSelectionDriver()) {
        let defaults = AppDefaults.store
        keyboardLayoutManager = KeyboardLayoutManager()
        hotKeyManager = HotKeyManager()
        textTransformer = TextTransformer()
        spellCheckManager = SpellCheckManager()
        accessibilityManager = AccessibilityManager()
        autoLaunchManager = AutoLaunchManager()
        notificationManager = NotificationManager()
        textProcessingManager = TextProcessingManager(
            textTransformer: textTransformer,
            keyboardLayoutManager: keyboardLayoutManager,
            spellCheckManager: spellCheckManager,
            notificationManager: notificationManager,
            driver: selectionDriver
        )
        smartLayoutManager = SmartLayoutManager(keyboardLayoutManager: keyboardLayoutManager)
        exclusionManager = ExclusionManager()
        hotkeyBlockerManager = HotkeyBlockerManager(notificationManager: notificationManager, exclusionManager: exclusionManager)
        autoConvertManager = AutoConvertManager(transformer: textTransformer, keyboardLayoutManager: keyboardLayoutManager)
        windowManager = WindowManager()

        // Off until the user opts in; sound and skipping code apps default to on.
        isAutoConvertEnabled = defaults.bool(forKey: DefaultsKeys.autoConvertEnabled)
        isAutoConvertSoundEnabled = defaults.object(forKey: DefaultsKeys.autoConvertSound) as? Bool ?? true
        isAutoConvertSkippingCodeApps = defaults.object(forKey: DefaultsKeys.autoConvertSkipCodeApps) as? Bool ?? true
        isAutoLaunchEnabled = autoLaunchManager.isEnabled
        // First launch: conversion on. Afterwards the saved choice wins.
        isTextConversionEnabled = defaults.object(forKey: DefaultsKeys.hotKeyMonitoringEnabled) as? Bool ?? true
        isSpellCheckEnabled = defaults.bool(forKey: DefaultsKeys.spellCheckEnabled)
        isCmdQBlockerEnabled = defaults.bool(forKey: DefaultsKeys.qblockerEnabled)
        isCmdWBlockerEnabled = defaults.bool(forKey: DefaultsKeys.wblockerEnabled)
        blockerDelay = hotkeyBlockerManager.delay
        hotkeyBlockerManager.isCmdQEnabled = isCmdQBlockerEnabled
        hotkeyBlockerManager.isCmdWEnabled = isCmdWBlockerEnabled
        layoutHotKeyDisplay = hotKeyManager.layoutHotKey.displayString
        spellCheckHotKeyDisplay = hotKeyManager.spellCheckHotKey.displayString

        autoConvertManager.playsSound = isAutoConvertSoundEnabled
        autoConvertManager.skipsTerminalsAndCodeEditors = isAutoConvertSkippingCodeApps
        autoConvertManager.isEnabled = isAutoConvertEnabled

        windowManager.setCoordinator(self)
        setupBindings()
    }

    private func setupBindings() {
        accessibilityManager.$isGranted
            .removeDuplicates()
            .sink { [weak self] granted in
                guard let self else { return }
                self.isAccessibilityGranted = granted
                self.applyServiceState()
            }
            .store(in: &cancellables)

        $isTextConversionEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                AppDefaults.store.set(enabled, forKey: DefaultsKeys.hotKeyMonitoringEnabled)
                self.applyServiceState(conversionEnabled: enabled)
            }
            .store(in: &cancellables)

        $isSpellCheckEnabled.dropFirst().removeDuplicates()
            .sink { AppDefaults.store.set($0, forKey: DefaultsKeys.spellCheckEnabled) }
            .store(in: &cancellables)

        $isAutoConvertEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in
                AppDefaults.store.set(enabled, forKey: DefaultsKeys.autoConvertEnabled)
                self?.autoConvertManager.isEnabled = enabled
            }
            .store(in: &cancellables)
        $isAutoConvertSoundEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in
                AppDefaults.store.set(enabled, forKey: DefaultsKeys.autoConvertSound)
                self?.autoConvertManager.playsSound = enabled
            }
            .store(in: &cancellables)
        $isAutoConvertSkippingCodeApps.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in
                AppDefaults.store.set(enabled, forKey: DefaultsKeys.autoConvertSkipCodeApps)
                self?.autoConvertManager.skipsTerminalsAndCodeEditors = enabled
            }
            .store(in: &cancellables)

        $isAutoLaunchEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in self?.setAutoLaunch(enabled) }
            .store(in: &cancellables)

        $isCmdQBlockerEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, self.hotkeyBlockerManager.isCmdQEnabled != enabled else { return }
                self.hotkeyBlockerManager.isCmdQEnabled = enabled
                self.hotkeyBlockerManager.saveSettings()
                if self.isAccessibilityGranted { self.hotkeyBlockerManager.updateMonitoringState() }
            }
            .store(in: &cancellables)

        $isCmdWBlockerEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, self.hotkeyBlockerManager.isCmdWEnabled != enabled else { return }
                self.hotkeyBlockerManager.isCmdWEnabled = enabled
                self.hotkeyBlockerManager.saveSettings()
                if self.isAccessibilityGranted { self.hotkeyBlockerManager.updateMonitoringState() }
            }
            .store(in: &cancellables)

        // The blocker switches itself off when its event taps fail; mirror that into the UI.
        hotkeyBlockerManager.$isCmdQEnabled.removeDuplicates()
            .sink { [weak self] enabled in
                if let self, self.isCmdQBlockerEnabled != enabled { self.isCmdQBlockerEnabled = enabled }
            }
            .store(in: &cancellables)
        hotkeyBlockerManager.$isCmdWEnabled.removeDuplicates()
            .sink { [weak self] enabled in
                if let self, self.isCmdWBlockerEnabled != enabled { self.isCmdWBlockerEnabled = enabled }
            }
            .store(in: &cancellables)

        $blockerDelay.dropFirst().removeDuplicates()
            .sink { [weak self] delay in
                guard let self else { return }
                self.hotkeyBlockerManager.delay = delay
                self.hotkeyBlockerManager.saveSettings()
            }
            .store(in: &cancellables)

        hotKeyManager.$isSecureInputActive
            .sink { [weak self] active in self?.isSecureInputActive = active }
            .store(in: &cancellables)
        hotKeyManager.$secureInputHolderName.sink { [weak self] in self?.secureInputHolderName = $0 }.store(in: &cancellables)
        hotKeyManager.$isSecureInputStale.sink { [weak self] in self?.isSecureInputStale = $0 }.store(in: &cancellables)
        hotKeyManager.$layoutHotKey.sink { [weak self] in self?.layoutHotKeyDisplay = $0.displayString }.store(in: &cancellables)
        hotKeyManager.$spellCheckHotKey.sink { [weak self] in self?.spellCheckHotKeyDisplay = $0.displayString }.store(in: &cancellables)

        keyboardLayoutManager.$currentLayout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.windowManager.refreshStatusButton() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .layoutHotKeyPressed)
            .sink { [weak self] _ in self?.handleHotKeyPressed(action: .changeLayout) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .spellCheckHotKeyPressed)
            .sink { [weak self] _ in
                guard let self, self.isSpellCheckEnabled else { return }
                self.handleHotKeyPressed(action: .fixSpelling)
            }
            .store(in: &cancellables)
    }

    /// Hotkeys run only when conversion is on and Accessibility is granted; blockers only with Accessibility.
    /// `@Published` sinks fire before the new value is stored, so the new value is passed in.
    private func applyServiceState(conversionEnabled: Bool? = nil) {
        if isAccessibilityGranted && (conversionEnabled ?? isTextConversionEnabled) {
            hotKeyManager.startMonitoring()
        } else {
            hotKeyManager.stopMonitoring()
        }

        autoConvertManager.canMonitor = isAccessibilityGranted

        if isAccessibilityGranted {
            hotkeyBlockerManager.updateMonitoringState()
        } else if hotkeyBlockerManager.isMonitoring {
            hotkeyBlockerManager.stop()
        }
        DispatchQueue.main.async { [weak self] in self?.windowManager.refreshStatusButton() }
    }

    private func setAutoLaunch(_ enabled: Bool) {
        do {
            try autoLaunchManager.setEnabled(enabled)
            autoLaunchError = autoLaunchManager.requiresApproval
                ? "Allow \(AppIdentity.displayName) in System Settings › General › Login Items."
                : nil
        } catch {
            autoLaunchError = error.localizedDescription
        }
        let actual = autoLaunchManager.isEnabled || autoLaunchManager.requiresApproval
        if actual != enabled {
            DispatchQueue.main.async { [weak self] in self?.isAutoLaunchEnabled = actual }
        }
    }

    func start() {
        debugLog("🚀 Started")
        guard !ProcessRuntime.shouldSkipAccessibilityPrompt else { return }
        if !accessibilityManager.isGranted {
            Task { await accessibilityManager.requestPermissions() }
        }
    }

    func stop() {
        hotKeyManager.stopMonitoring()
        hotkeyBlockerManager.stop()
        autoConvertManager.isEnabled = false
    }

    // MARK: - Hotkeys

    private func handleHotKeyPressed(action: ProcessingAction) {
        guard isAccessibilityGranted else {
            notificationManager.showHUD(text: "Accessibility access needed", symbol: "exclamationmark.triangle", duration: 1.5)
            Task { await accessibilityManager.requestPermissions() }
            return
        }
        guard !textProcessingManager.isProcessing else { return }
        textProcessingManager.processSelectedText(action: action)
    }

    /// Same path as a real hotkey press — for integration tests.
    func triggerConversionForTesting(_ action: ProcessingAction) {
        handleHotKeyPressed(action: action)
    }

    // MARK: - Interface

    var layoutHotKey: HotKey {
        get { hotKeyManager.layoutHotKey }
        set { hotKeyManager.updateLayoutHotKey(newValue) }
    }

    var spellCheckHotKey: HotKey {
        get { hotKeyManager.spellCheckHotKey }
        set { hotKeyManager.updateSpellCheckHotKey(newValue) }
    }

    /// Pause global hotkeys while the recorder listens, so the current shortcut can be typed.
    func stopKeyCapture() {
        hotKeyManager.stopMonitoring()
    }

    func startKeyCapture() {
        guard isTextConversionEnabled, isAccessibilityGranted else { return }
        hotKeyManager.startMonitoring()
    }

    func recheckSecureInput() {
        hotKeyManager.recheckSecureInput()
    }

    var secureInputStatusMessage: String {
        if isSecureInputStale {
            return "The app that turned it on has quit, but macOS kept it on. Lock the screen (⌃⌘Q) and log back in."
        }
        if let secureInputHolderName, !secureInputHolderName.isEmpty {
            return "\(secureInputHolderName) has Secure Input on. Conversion still works; ⌘Q/⌘W protection may not."
        }
        return "Another app has Secure Input on. Conversion still works; ⌘Q/⌘W protection may not."
    }
}
