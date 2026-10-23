import AppKit

/// Hold-to-confirm for ⌘Q and ⌘W. A quick press is swallowed and counted; holding for `delay`
/// seconds sends the shortcut to the app, so it quits or closes through its own menu (with save prompts).
///
/// One event tap on the main run loop: the callback only compares a key code and flips a few flags,
/// so there is no separate thread and no shared state to race on.
final class HotkeyBlockerManager: ObservableObject {
    @Published var isCmdQEnabled = false
    @Published var isCmdWEnabled = false
    @Published var accidentalQuits: Int
    @Published var accidentalCloses: Int
    @Published var delay: Int
    /// Set when the event tap could not be created; both protections are switched off then.
    @Published var startupError: String?

    /// Integration tests: completed holds don't send ⌘Q / ⌘W.
    var suppressSideEffectsForTesting = false

    private enum Shortcut: Int64 {
        case quit = 12   // Q
        case close = 13  // W

        var label: String { self == .quit ? "Hold ⌘Q to quit" : "Hold ⌘W to close" }
        var symbol: String { self == .quit ? "power" : "xmark.square" }
    }

    private struct Hold {
        let shortcut: Shortcut
        let bundleID: String?
        var completed = false
        var timer: DispatchWorkItem?
    }

    private let notificationManager: NotificationManager
    private let exclusionManager: ExclusionManager
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var hold: Hold?
    private var frontmostBundleID: String?
    /// bundle ID → whether its menu has a plain ⌘Q item (apps without one, like Finder, are left alone).
    private var quitItemCache: [String: Bool] = [:]
    private var activationObserver: NSObjectProtocol?

    init(notificationManager: NotificationManager, exclusionManager: ExclusionManager) {
        self.notificationManager = notificationManager
        self.exclusionManager = exclusionManager
        let defaults = AppDefaults.store
        accidentalQuits = defaults.integer(forKey: DefaultsKeys.qblockerAccidentalQuits)
        accidentalCloses = defaults.integer(forKey: DefaultsKeys.wblockerAccidentalCloses)
        delay = (defaults.object(forKey: DefaultsKeys.qblockerDelay) as? Int).map { min(max($0, 1), 5) } ?? 1
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationActivated(app.bundleIdentifier)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        stop()
    }

    // MARK: - Settings

    func saveSettings() {
        let defaults = AppDefaults.store
        defaults.set(isCmdQEnabled, forKey: DefaultsKeys.qblockerEnabled)
        defaults.set(isCmdWEnabled, forKey: DefaultsKeys.wblockerEnabled)
        defaults.set(accidentalQuits, forKey: DefaultsKeys.qblockerAccidentalQuits)
        defaults.set(accidentalCloses, forKey: DefaultsKeys.wblockerAccidentalCloses)
        defaults.set(delay, forKey: DefaultsKeys.qblockerDelay)
    }

    func resetStatistics() {
        accidentalQuits = 0
        accidentalCloses = 0
        saveSettings()
    }

    // MARK: - Lifecycle

    var isMonitoring: Bool { tap != nil }

    /// Starts or stops the tap to match the toggles. Safe to call any number of times.
    func updateMonitoringState() {
        if isCmdQEnabled || isCmdWEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard tap == nil, isCmdQEnabled || isCmdWEnabled else { return }
        startupError = nil
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: blockerTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            isCmdQEnabled = false
            isCmdWEnabled = false
            saveSettings()
            startupError = "Quit protection needs Accessibility access."
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = source
    }

    func stop() {
        cancelHold()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        tap = nil
        tapSource = nil
    }

    // MARK: - Event tap

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            guard event.getIntegerValueField(.eventSourceUserData) != KeystrokeOutput.marker else {
                return Unmanaged.passUnretained(event)
            }
            let flags = event.flags
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let command = flags.contains(.maskCommand)
            let other = !flags.isDisjoint(with: [.maskShift, .maskControl, .maskAlternate])
            if type == .keyDown {
                let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                return handleKeyDown(keyCode: keyCode, command: command, otherModifiers: other, isAutorepeat: repeated)
                    ? nil : Unmanaged.passUnretained(event)
            }
            handleKeyUp(keyCode: keyCode)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Decisions (also driven directly by tests)

    /// Returns `true` when the key is swallowed.
    @discardableResult
    func handleSyntheticKeyDown(keyCode: Int, commandDown: Bool, shiftDown: Bool = false, controlDown: Bool = false, isAutorepeat: Bool = false) -> Bool {
        handleKeyDown(keyCode: keyCode, command: commandDown, otherModifiers: shiftDown || controlDown, isAutorepeat: isAutorepeat)
    }

    func handleSyntheticKeyUp(keyCode: Int, commandDown: Bool, shiftDown: Bool = false, controlDown: Bool = false) {
        handleKeyUp(keyCode: keyCode)
    }

    private func handleKeyDown(keyCode: Int, command: Bool, otherModifiers: Bool, isAutorepeat: Bool) -> Bool {
        guard command, !otherModifiers, let shortcut = Shortcut(rawValue: Int64(keyCode)) else { return false }
        guard shortcut == .quit ? isCmdQEnabled : isCmdWEnabled else { return false }

        // A hold already running (or just completed) for this key: swallow autorepeat until key up.
        if let hold, hold.shortcut == shortcut { return true }
        guard HoldDurationLogic.shouldBeginHold(isAlreadyHolding: hold != nil, isAutorepeat: isAutorepeat) else { return true }

        let bundleID = frontmostBundleID
        if let bundleID, exclusionManager.isAppExcluded(bundleID: bundleID) { return false }
        if shortcut == .quit, let bundleID, !appHasQuitItem(bundleID) { return false }

        let timer = DispatchWorkItem { [weak self] in self?.completeHold() }
        hold = Hold(shortcut: shortcut, bundleID: bundleID, timer: timer)
        notificationManager.showHUD(text: shortcut.label, symbol: shortcut.symbol, duration: TimeInterval(delay))
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(delay), execute: timer)
        return true
    }

    private func handleKeyUp(keyCode: Int) {
        guard let current = hold, current.shortcut.rawValue == Int64(keyCode) else { return }
        if !current.completed {
            if current.shortcut == .quit { accidentalQuits += 1 } else { accidentalCloses += 1 }
            saveSettings()
        }
        cancelHold()
    }

    private func completeHold() {
        guard var current = hold, !current.completed else { return }
        current.completed = true
        current.timer = nil
        hold = current
        notificationManager.dismissHUD()
        guard !suppressSideEffectsForTesting else { return }
        sendShortcut(current.shortcut)
    }

    private func cancelHold() {
        hold?.timer?.cancel()
        hold = nil
        notificationManager.dismissHUD()
    }

    /// Posted below our HID tap (session level) and marked, so the tap never sees it.
    private func sendShortcut(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.rawValue), keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: KeystrokeOutput.marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func applicationActivated(_ bundleID: String?) {
        // Our own HUD must not cancel a hold in the app underneath.
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        frontmostBundleID = bundleID
        if let hold, hold.bundleID != bundleID {
            cancelHold()
        }
    }

    /// Unknown (no Accessibility, no menu bar) counts as "has ⌘Q", so protection stays on.
    private func appHasQuitItem(_ bundleID: String) -> Bool {
        if let cached = quitItemCache[bundleID] { return cached }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID,
              let menuBar = AX.element(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute) else {
            return true
        }
        let appMenu = AX.children(menuBar).dropFirst().first.flatMap { AX.children($0).first }
        guard let appMenu else { return true }
        let hasQuit = AX.children(appMenu).contains { item in
            AX.attribute(item, kAXMenuItemCmdCharAttribute) as? String == "Q"
                && AX.attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int == 0
        }
        quitItemCache[bundleID] = hasQuit
        return hasQuit
    }
}

private func blockerTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotkeyBlockerManager>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
