import Foundation
import Carbon
import AppKit

// MARK: - Hot Key Manager
final class HotKeyManager: ObservableObject {
    private enum RegisteredHotKeyID: UInt32 {
        case layout = 1
        case spellCheck = 2
    }

    @Published var layoutHotKey: HotKey = HotKey(keyCode: 18, modifiers: [.maskCommand])
    @Published var spellCheckHotKey: HotKey = HotKey(keyCode: 19, modifiers: [.maskCommand])

    @Published var isEnabled: Bool = false
    @Published var isSecureInputActive: Bool = false
    @Published private(set) var secureInputHolderName: String?
    @Published private(set) var isSecureInputStale: Bool = false

    private var layoutHotKeyRef: EventHotKeyRef?
    private var spellCheckHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let secureInputMonitor = SecureInputMonitor()

    private static let hotKeySignature: OSType = 0x7472796C // "tryl"

    init() {
        loadHotKeys()
        startSecureInputMonitoring()
    }

    deinit {
        if Thread.isMainThread {
            unregisterLayoutHotKey()
            unregisterSpellCheckHotKey()
        }
        secureInputMonitor.stop()
    }

    // MARK: - Hot Key Management

    func loadHotKeys() {
        let decoder = JSONDecoder()

        if let savedLayout = AppDefaults.store.data(forKey: DefaultsKeys.savedLayoutHotKey) {
            do {
                layoutHotKey = try decoder.decode(HotKey.self, from: savedLayout)
            } catch {
                debugLog("❌ Failed to load layout hotkey: \(error)")
            }
        } else if let legacyHotKey = AppDefaults.store.data(forKey: DefaultsKeys.savedHotKey) {
            do {
                layoutHotKey = try decoder.decode(HotKey.self, from: legacyHotKey)
            } catch {
                debugLog("❌ Failed to load legacy hotkey: \(error)")
            }
        }

        if let savedSpell = AppDefaults.store.data(forKey: DefaultsKeys.savedSpellCheckHotKey) {
            do {
                spellCheckHotKey = try decoder.decode(HotKey.self, from: savedSpell)
            } catch {
                debugLog("❌ Failed to load spelling hotkey: \(error)")
            }
        }
    }

    func saveHotKeys() {
        let encoder = JSONEncoder()

        do {
            let layoutData = try encoder.encode(layoutHotKey)
            AppDefaults.store.set(layoutData, forKey: DefaultsKeys.savedLayoutHotKey)
            AppDefaults.store.set(layoutData, forKey: DefaultsKeys.savedHotKey)
        } catch {
            debugLog("❌ Failed to save layout hotkey: \(error)")
        }

        do {
            let spellData = try encoder.encode(spellCheckHotKey)
            AppDefaults.store.set(spellData, forKey: DefaultsKeys.savedSpellCheckHotKey)
        } catch {
            debugLog("❌ Failed to save spelling hotkey: \(error)")
        }
    }

    func updateLayoutHotKey(_ newHotKey: HotKey) {
        layoutHotKey = newHotKey
        saveHotKeys()
        debugLog("🔄 Hotkey updated: \(newHotKey.displayString)")
        if isEnabled {
            runOnMain { self.registerLayoutHotKey() }
        }
    }

    func updateSpellCheckHotKey(_ newHotKey: HotKey) {
        spellCheckHotKey = newHotKey
        saveHotKeys()
        debugLog("🔄 Spelling hotkey updated: \(newHotKey.displayString)")
        if isEnabled {
            runOnMain { self.registerSpellCheckHotKey() }
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        runOnMain {
            guard !self.isEnabled else { return }

            self.installEventHandlerIfNeeded()
            self.registerLayoutHotKey()
            self.registerSpellCheckHotKey()
            self.isEnabled = true
            debugLog("✅ Hotkeys registered")
        }
    }

    func stopMonitoring() {
        runOnMain {
            guard self.isEnabled || self.layoutHotKeyRef != nil || self.spellCheckHotKeyRef != nil else { return }

            self.unregisterLayoutHotKey()
            self.unregisterSpellCheckHotKey()
            self.isEnabled = false
            debugLog("⏹️ Hotkeys unregistered")
        }
    }

    // MARK: - Carbon Hot Keys

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleCarbonHotKey(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            debugLog("❌ InstallEventHandler failed: \(status)")
        }
    }

    private func handleCarbonHotKey(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return status }

        // Carbon delivers application-target hotkeys on the main thread already.
        switch hotKeyID.id {
        case RegisteredHotKeyID.layout.rawValue:
            NotificationCenter.default.post(name: .layoutHotKeyPressed, object: nil)
        case RegisteredHotKeyID.spellCheck.rawValue:
            NotificationCenter.default.post(name: .spellCheckHotKeyPressed, object: nil)
        default:
            break
        }

        return noErr
    }

    private func registerLayoutHotKey() {
        unregisterLayoutHotKey()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: RegisteredHotKeyID.layout.rawValue)
        let status = RegisterEventHotKey(
            UInt32(layoutHotKey.keyCode),
            carbonModifiers(for: layoutHotKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            layoutHotKeyRef = ref
        } else {
            debugLog("❌ RegisterEventHotKey layout failed: \(status)")
        }
    }

    private func registerSpellCheckHotKey() {
        unregisterSpellCheckHotKey()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: RegisteredHotKeyID.spellCheck.rawValue)
        let status = RegisterEventHotKey(
            UInt32(spellCheckHotKey.keyCode),
            carbonModifiers(for: spellCheckHotKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            spellCheckHotKeyRef = ref
        } else {
            debugLog("❌ RegisterEventHotKey spell check failed: \(status)")
        }
    }

    private func unregisterLayoutHotKey() {
        if let layoutHotKeyRef {
            UnregisterEventHotKey(layoutHotKeyRef)
            self.layoutHotKeyRef = nil
        }
    }

    private func unregisterSpellCheckHotKey() {
        if let spellCheckHotKeyRef {
            UnregisterEventHotKey(spellCheckHotKeyRef)
            self.spellCheckHotKeyRef = nil
        }
    }

    private func carbonModifiers(for hotKey: HotKey) -> UInt32 {
        var modifiers: UInt32 = 0
        for flag in hotKey.modifiers {
            if flag.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
            if flag.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
            if flag.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
            if flag.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        }
        return modifiers
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    // MARK: - Secure Input Monitoring

    private func startSecureInputMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.secureInputMonitor.onChange = { [weak self] status in
                guard let self else { return }
                self.isSecureInputActive = status.isActive
                self.secureInputHolderName = status.holderProcessName
                self.isSecureInputStale = status.isStaleHolder
            }
            self.secureInputMonitor.start()
            debugLog("✅ Secure Input monitoring started")
        }
    }

    func recheckSecureInput() {
        DispatchQueue.main.async { [weak self] in
            self?.secureInputMonitor.recheck()
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let layoutHotKeyPressed = Notification.Name("layoutHotKeyPressed")
    static let spellCheckHotKeyPressed = Notification.Name("spellCheckHotKeyPressed")
}
