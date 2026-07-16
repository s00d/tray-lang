import Foundation
import AppKit
import Carbon

// MARK: - Hotkey Blocker Manager
class HotkeyBlockerManager: ObservableObject {
    // MARK: - Properties
    // 1. УБИРАЕМ didSet. Теперь это просто свойства.
    @Published var isCmdQEnabled: Bool = false
    @Published var isCmdWEnabled: Bool = false
    
    @Published var accidentalQuits: Int = 0
    @Published var accidentalCloses: Int = 0
    @Published var delay: Int = 1
    
    private var cmdQHoldStartedAt: Date?
    private var cmdWHoldStartedAt: Date?
    private var cmdQHoldTargetBundleID: String?
    private var cmdWHoldTargetBundleID: String?
    private var cmdQHoldCompleted = false
    private var cmdWHoldCompleted = false
    private var cmdQHoldTimer: DispatchWorkItem?
    private var cmdWHoldTimer: DispatchWorkItem?
    private var canQuit: Bool = true
    private var canClose: Bool = true
    
    // Используются в callback функциях, поэтому не могут быть private
    var keyDownEventTap: CFMachPort?
    var keyUpEventTap: CFMachPort?
    private var keyDownRunLoopSource: CFRunLoopSource?
    private var keyUpRunLoopSource: CFRunLoopSource?
    
    private var isTapUserInfoRetained = false
    
    // Отдельный поток для мониторинга клавиатуры
    private var monitoringThread: Thread?
    private var monitoringRunLoop: CFRunLoop?
    
    // Кэш для оптимизации проверки Cmd+Q
    private var currentAppBundleID: String?
    private var currentAppSupportsCmdQ: Bool = true // По умолчанию true для безопасности
    
    // Throttling для счетчиков
    private var internalAccidentalQuits = 0
    private var internalAccidentalCloses = 0
    
    private let notificationManager: NotificationManager
    private let exclusionManager: ExclusionManager

    /// When true, completed holds do not terminate apps / post Cmd+W (integration tests).
    var suppressSideEffectsForTesting = false
    
    init(notificationManager: NotificationManager, exclusionManager: ExclusionManager) {
        self.notificationManager = notificationManager
        self.exclusionManager = exclusionManager
        // 2. УБИРАЕМ loadSettings() из init. AppCoordinator сам задаст начальные значения.
        // Загружаем только статистику и задержку
        self.internalAccidentalQuits = UserDefaults.standard.integer(forKey: DefaultsKeys.qblockerAccidentalQuits)
        self.internalAccidentalCloses = UserDefaults.standard.integer(forKey: DefaultsKeys.wblockerAccidentalCloses)
        self.accidentalQuits = internalAccidentalQuits
        self.accidentalCloses = internalAccidentalCloses
        if UserDefaults.standard.object(forKey: DefaultsKeys.qblockerDelay) == nil {
            self.delay = 1
        } else {
            self.delay = UserDefaults.standard.integer(forKey: DefaultsKeys.qblockerDelay)
        }
        
        // Подписываемся на смену приложения для кэширования проверки Cmd+Q
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stop()
    }
    
    // MARK: - Settings Management
    // loadSettings() удален - AppCoordinator сам задает начальные значения
    func saveSettings() {
        UserDefaults.standard.set(isCmdQEnabled, forKey: DefaultsKeys.qblockerEnabled)
        UserDefaults.standard.set(isCmdWEnabled, forKey: DefaultsKeys.wblockerEnabled)
        UserDefaults.standard.set(internalAccidentalQuits, forKey: DefaultsKeys.qblockerAccidentalQuits)
        UserDefaults.standard.set(internalAccidentalCloses, forKey: DefaultsKeys.wblockerAccidentalCloses)
        UserDefaults.standard.set(delay, forKey: DefaultsKeys.qblockerDelay)
    }
    
    // MARK: - Lifecycle
    func start() {
        guard isCmdQEnabled || isCmdWEnabled else { return }
        
        // Проверяем, не запущен ли уже мониторинг
        if isMonitoring {
            debugLog("ℹ️ HotkeyBlocker monitoring is already active")
            return
        }
        
        // Создаем поток для мониторинга
        monitoringThread = Thread { [weak self] in
            guard let self = self else { return }
            
            // Внутри потока создаем Event Tap
            do {
                try self.startKeyMonitoring()
                
                // Сохраняем ссылку на RunLoop
                self.monitoringRunLoop = CFRunLoopGetCurrent()
                
                // Запускаем RunLoop этого потока
                CFRunLoopRun()
            } catch {
                debugLog("❌ Error starting tap on thread: \(error)")
                DispatchQueue.main.async {
                    self.handleStartupError(error)
                }
            }
        }
        
        monitoringThread?.name = "com.traylang.keyboardMonitor"
        monitoringThread?.qualityOfService = .userInteractive
        monitoringThread?.start()
        
        debugLog("✅ HotkeyBlocker monitoring thread started")
    }
    
    func stop() {
        // Останавливаем RunLoop потока
        if let runLoop = monitoringRunLoop {
            CFRunLoopStop(runLoop)
        }
        
        stopKeyMonitoring()
        
        // Отменяем поток
        monitoringThread?.cancel()
        monitoringThread = nil
        monitoringRunLoop = nil
        
        debugLog("⏹️ HotkeyBlocker monitoring stopped")
    }
    
    // 4. УПРОЩАЕМ updateMonitoringState. Теперь он просто слушается AppCoordinator.
    func updateMonitoringState() {
        debugLog("🔄 Updating monitoring state...")
        debugLog("  📋 Current state: Cmd+Q: \(isCmdQEnabled), Cmd+W: \(isCmdWEnabled)")
        debugLog("  📋 Monitoring active: \(isMonitoring)")
        
        // Сохраняем настройки при изменении
        saveSettings()
        
        // Если нужно включить мониторинг и он не активен
        if (isCmdQEnabled || isCmdWEnabled) && !isMonitoring {
            debugLog("  🚀 Starting monitoring...")
            start()
        }
        // Если нужно выключить мониторинг и он активен
        else if !isCmdQEnabled && !isCmdWEnabled && isMonitoring {
            debugLog("  ⏹️ Stopping monitoring...")
            stop()
        }
        // Если состояние изменилось, но мониторинг уже в нужном состоянии
        else {
            debugLog("  ℹ️ Monitoring state is already correct")
        }
    }
    
    var isMonitoring: Bool {
        return keyDownEventTap != nil && keyUpEventTap != nil
    }
    
    // MARK: - Key Monitoring
    private func startKeyMonitoring() throws {
        let retainedSelf = Unmanaged.passRetained(self)
        isTapUserInfoRetained = true
        let userInfo = retainedSelf.toOpaque()
        
        keyDownEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: keyDownCallback,
            userInfo: userInfo
        )
        
        keyUpEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyUp.rawValue),
            callback: keyUpCallback,
            userInfo: userInfo
        )
        
        guard keyDownEventTap != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyDown event tap - accessibility permissions may be denied")
            releaseTapUserInfo()
            throw QBlockerError.AccessibilityPermissionDenied
        }
        
        guard keyUpEventTap != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyUp event tap - accessibility permissions may be denied")
            releaseTapUserInfo()
            throw QBlockerError.AccessibilityPermissionDenied
        }
        
        // Create run loop sources
        keyDownRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyDownEventTap, 0)
        guard keyDownRunLoopSource != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyDown run loop source")
            releaseTapUserInfo()
            throw QBlockerError.RunLoopSourceCreationFailed
        }
        
        keyUpRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyUpEventTap, 0)
        guard keyUpRunLoopSource != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyUp run loop source")
            releaseTapUserInfo()
            throw QBlockerError.RunLoopSourceCreationFailed
        }
        
        // Add sources to run loop (будет вызвано из monitoringThread)
        let currentRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(currentRunLoop, keyDownRunLoopSource, .commonModes)
        CFRunLoopAddSource(currentRunLoop, keyUpRunLoopSource, .commonModes)
        
        debugLog("✅ HotkeyBlocker: Event taps created and added to run loop successfully")
    }
    
    private func stopKeyMonitoring() {
        if let keyDownEventTap = keyDownEventTap {
            CGEvent.tapEnable(tap: keyDownEventTap, enable: false)
            CFMachPortInvalidate(keyDownEventTap)
        }
        
        if let keyUpEventTap = keyUpEventTap {
            CGEvent.tapEnable(tap: keyUpEventTap, enable: false)
            CFMachPortInvalidate(keyUpEventTap)
        }
        
        if let keyDownRunLoopSource = keyDownRunLoopSource, let runLoop = monitoringRunLoop {
            CFRunLoopRemoveSource(runLoop, keyDownRunLoopSource, .commonModes)
        }
        
        if let keyUpRunLoopSource = keyUpRunLoopSource, let runLoop = monitoringRunLoop {
            CFRunLoopRemoveSource(runLoop, keyUpRunLoopSource, .commonModes)
        }
        
        releaseTapUserInfo()
        
        keyDownEventTap = nil
        keyUpEventTap = nil
        keyDownRunLoopSource = nil
        keyUpRunLoopSource = nil
    }
    
    private func releaseTapUserInfo() {
        if isTapUserInfoRetained {
            Unmanaged.passUnretained(self).release()
            isTapUserInfoRetained = false
        }
    }
    
    private func handleStartupError(_ error: Error) {
        isCmdQEnabled = false
        isCmdWEnabled = false
        saveSettings()
        
        switch error {
        case QBlockerError.AccessibilityPermissionDenied:
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "HotkeyBlocker requires accessibility permissions to monitor Cmd+Q and Cmd+W. Please enable accessibility access in System Preferences > Security & Privacy > Privacy > Accessibility.",
                style: .warning
            )
        case QBlockerError.EventTapCreationFailed:
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "Failed to create event monitoring for HotkeyBlocker. This may be due to system restrictions.",
                style: .warning
            )
        case QBlockerError.RunLoopSourceCreationFailed:
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "Failed to initialize HotkeyBlocker monitoring. Please try restarting the application.",
                style: .warning
            )
        default:
            notificationManager.showAlert(
                title: "HotkeyBlocker Error",
                message: "An unexpected error occurred while starting HotkeyBlocker: \(error.localizedDescription)",
                style: .warning
            )
        }
    }
    
    // MARK: - Event Handling

    /// Synthetic key path for tests — same swallow/pass semantics as the CGEvent taps.
    /// Returns `true` when the key would be blocked (event swallowed).
    @discardableResult
    func handleSyntheticKeyDown(
        keyCode: Int,
        commandDown: Bool,
        shiftDown: Bool = false,
        controlDown: Bool = false,
        isAutorepeat: Bool = false
    ) -> Bool {
        processKeyDown(
            keyCode: keyCode,
            commandDown: commandDown,
            shiftDown: shiftDown,
            controlDown: controlDown,
            isAutorepeat: isAutorepeat
        ) == .swallowed
    }

    @discardableResult
    func handleSyntheticKeyUp(
        keyCode: Int,
        commandDown: Bool,
        shiftDown: Bool = false,
        controlDown: Bool = false
    ) -> Bool {
        processKeyUp(
            keyCode: keyCode,
            commandDown: commandDown,
            shiftDown: shiftDown,
            controlDown: controlDown
        ) == .swallowed
    }

    private enum KeyDisposition {
        case passThrough
        case swallowed
    }

    private func processKeyDown(
        keyCode: Int,
        commandDown: Bool,
        shiftDown: Bool,
        controlDown: Bool,
        isAutorepeat: Bool
    ) -> KeyDisposition {
        debugLog("🔍 HotkeyBlocker: KeyDown event received")
        debugLog("  📋 Cmd: \(commandDown) Shift: \(shiftDown) Control: \(controlDown) KeyCode: \(keyCode)")

        guard commandDown else {
            debugLog("  ❌ No Cmd key, passing through")
            return .passThrough
        }

        guard !shiftDown && !controlDown else {
            debugLog("  ❌ Shift or Control pressed, passing through")
            return .passThrough
        }

        if keyCode == 12 && isCmdQEnabled {
            return handleCmdQDown(isAutorepeat: isAutorepeat)
        }

        if keyCode == 13 && isCmdWEnabled {
            return handleCmdWDown(isAutorepeat: isAutorepeat)
        }

        debugLog("  ❌ Not Q or W key, passing through")
        return .passThrough
    }

    private func processKeyUp(
        keyCode: Int,
        commandDown: Bool,
        shiftDown: Bool,
        controlDown: Bool
    ) -> KeyDisposition {
        debugLog("🔍 HotkeyBlocker: KeyUp event received")

        guard commandDown else { return .passThrough }
        guard !shiftDown && !controlDown else { return .passThrough }

        if keyCode == 12 && isCmdQEnabled {
            handleCmdQUp()
            return .passThrough
        }

        if keyCode == 13 && isCmdWEnabled {
            handleCmdWUp()
            return .passThrough
        }

        return .passThrough
    }

    func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = getKeyCode(from: event)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let disposition = processKeyDown(
            keyCode: keyCode,
            commandDown: flags.contains(.maskCommand),
            shiftDown: flags.contains(.maskShift),
            controlDown: flags.contains(.maskControl),
            isAutorepeat: isRepeat
        )
        return disposition == .swallowed ? nil : Unmanaged.passUnretained(event)
    }
    
    // Обработка отключения Event Tap системой (используется в callback, не может быть private)
    func handleTapDisabled(type: CGEventType, tap: CFMachPort) {
        debugLog("⚠️ HotkeyBlocker: Event Tap disabled by system (type: \(type.rawValue)). Attempting to re-enable...")
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLog("🔄 HotkeyBlocker: Event Tap re-enabled")
    }
    
    // Обработчик смены приложения (работает в фоне)
    @objc private func appChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        // Our own HUD panel must not cancel an in-progress hold in the foreground app.
        if bundleID == Bundle.main.bundleIdentifier {
            return
        }

        self.currentAppBundleID = bundleID

        if cmdQHoldStartedAt != nil,
           let target = cmdQHoldTargetBundleID,
           bundleID != target {
            cancelCmdQHold()
        }

        if cmdWHoldStartedAt != nil,
           let target = cmdWHoldTargetBundleID,
           bundleID != target {
            cancelCmdWHold()
        }
        
        // АСИНХРОННАЯ проверка (не блокирует UI)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let hasQuit = self.checkIfAppHasQuitMenuItem(app)
            DispatchQueue.main.async {
                self.currentAppSupportsCmdQ = hasQuit
                debugLog("  📋 Cached Cmd+Q support for \(bundleID): \(hasQuit)")
            }
        }
    }
    
    // Переименовываем старый метод для использования в фоне
    private func checkIfAppHasQuitMenuItem(_ app: NSRunningApplication) -> Bool {
        return isCmdQActive(for: app)
    }
    
    private func handleCmdQDown(isAutorepeat: Bool) -> KeyDisposition {
        debugLog("  ✅ Cmd+Q detected!")
        
        // Быстрая проверка исключений по строке (без API вызовов)
        if let bundleID = currentAppBundleID, exclusionManager.isAppExcluded(bundleID: bundleID) {
            debugLog("  ⚠️ Current app is excluded from protection")
            return .passThrough
        }
        
        // Читаем кэшированное значение (мгновенно)
        if !currentAppSupportsCmdQ {
            debugLog("  ❌ Cmd+Q not active for this app (cached), passing through")
            return .passThrough
        }
        
        // Check canQuit first
        guard canQuit else {
            debugLog("  ❌ Not allowed to quit yet")
            return .swallowed
        }
        
        guard HoldDurationLogic.shouldBeginHold(
            isAlreadyHolding: cmdQHoldStartedAt != nil,
            isAutorepeat: isAutorepeat
        ) else {
            return .swallowed
        }
        
        let requiredHold = TimeInterval(delay)
        cmdQHoldStartedAt = Date()
        cmdQHoldTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? currentAppBundleID
        cmdQHoldCompleted = false
        debugLog("  📱 Showing HUD for \(delay)s hold")
        showHUD(delayTime: requiredHold, hotkey: "Cmd+Q")
        
        let work = DispatchWorkItem { [weak self] in
            self?.completeCmdQHold()
        }
        cmdQHoldTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + requiredHold, execute: work)
        
        return .swallowed
    }
    
    private func completeCmdQHold() {
        guard let startedAt = cmdQHoldStartedAt, !cmdQHoldCompleted, canQuit else { return }
        guard HoldDurationLogic.hasHeldLongEnough(
            startedAt: startedAt,
            now: Date(),
            requiredSeconds: TimeInterval(delay)
        ) else { return }
        
        debugLog("🔓 HotkeyBlocker: Quit allowed after holding for \(delay) seconds")
        cmdQHoldCompleted = true
        canQuit = false
        hideHUD()

        if suppressSideEffectsForTesting {
            debugLog("🧪 HotkeyBlocker: suppressSideEffectsForTesting — skip terminate")
            return
        }
        
        guard let currentApp = NSWorkspace.shared.menuBarOwningApplication else { return }
        
        if let bundleID = currentApp.bundleIdentifier,
           exclusionManager.isAppExcluded(bundleID: bundleID) {
            debugLog("⚠️ HotkeyBlocker: App became excluded before quit, aborting")
            return
        }
        
        if !isCmdQActive(for: currentApp) {
            debugLog("⚠️ HotkeyBlocker: Cmd+Q no longer active for app, aborting quit")
            return
        }
        
        debugLog("🚪 HotkeyBlocker: Terminating \(currentApp.localizedName ?? "Unknown")")
        
        if let runningApp = NSRunningApplication(processIdentifier: currentApp.processIdentifier) {
            if runningApp.terminate() {
                debugLog("✅ HotkeyBlocker: Successfully terminated \(currentApp.localizedName ?? "Unknown")")
            } else if runningApp.forceTerminate() {
                debugLog("✅ HotkeyBlocker: Successfully force terminated \(currentApp.localizedName ?? "Unknown")")
            } else {
                debugLog("❌ HotkeyBlocker: Failed to force terminate, falling back to AppleScript")
                terminateAppViaAppleScript(currentApp)
            }
        } else {
            debugLog("❌ HotkeyBlocker: Could not create NSRunningApplication, falling back to AppleScript")
            terminateAppViaAppleScript(currentApp)
        }
    }
    
    private func handleCmdWDown(isAutorepeat: Bool) -> KeyDisposition {
        debugLog("  ✅ Cmd+W detected!")
        
        if exclusionManager.isCurrentAppExcluded() {
            debugLog("  ⚠️ Current app is excluded from protection")
            return .passThrough
        }
        
        guard canClose else {
            debugLog("  ❌ Not allowed to close yet")
            return .swallowed
        }
        
        guard HoldDurationLogic.shouldBeginHold(
            isAlreadyHolding: cmdWHoldStartedAt != nil,
            isAutorepeat: isAutorepeat
        ) else {
            return .swallowed
        }
        
        let requiredHold = TimeInterval(delay)
        cmdWHoldStartedAt = Date()
        cmdWHoldTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? currentAppBundleID
        cmdWHoldCompleted = false
        debugLog("  📱 Showing HUD for \(delay)s hold")
        showHUD(delayTime: requiredHold, hotkey: "Cmd+W")
        
        let work = DispatchWorkItem { [weak self] in
            self?.completeCmdWHold()
        }
        cmdWHoldTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + requiredHold, execute: work)
        
        return .swallowed
    }
    
    private func completeCmdWHold() {
        guard let startedAt = cmdWHoldStartedAt, !cmdWHoldCompleted, canClose else { return }
        guard HoldDurationLogic.hasHeldLongEnough(
            startedAt: startedAt,
            now: Date(),
            requiredSeconds: TimeInterval(delay)
        ) else { return }
        
        debugLog("🔓 HotkeyBlocker: Close allowed after holding for \(delay) seconds")
        cmdWHoldCompleted = true
        canClose = false
        hideHUD()

        if suppressSideEffectsForTesting {
            debugLog("🧪 HotkeyBlocker: suppressSideEffectsForTesting — skip Cmd+W post")
            return
        }
        
        debugLog("🚪 HotkeyBlocker: Sending Cmd+W to close window")
        if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true) {
            newEvent.flags = .maskCommand
            newEvent.post(tap: .cghidEventTap)
        }
    }
    
    func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = getKeyCode(from: event)
        _ = processKeyUp(
            keyCode: keyCode,
            commandDown: flags.contains(.maskCommand),
            shiftDown: flags.contains(.maskShift),
            controlDown: flags.contains(.maskControl)
        )
        return Unmanaged.passUnretained(event)
    }
    
    private func handleCmdQUp() {
        debugLog("  ✅ KeyUp: Q key detected")
        
        if cmdQHoldStartedAt != nil && !cmdQHoldCompleted {
            debugLog("📊 HotkeyBlocker: Accidental quit prevented! Total: \(accidentalQuits)")
            logAccidentalQuit()
        }
        
        cancelCmdQHold()
        canQuit = true
    }
    
    private func handleCmdWUp() {
        debugLog("  ✅ KeyUp: W key detected")
        
        if cmdWHoldStartedAt != nil && !cmdWHoldCompleted {
            debugLog("📊 HotkeyBlocker: Accidental close prevented! Total: \(accidentalCloses)")
            logAccidentalClose()
        }
        
        cancelCmdWHold()
        canClose = true
    }
    
    private func cancelCmdQHold() {
        cmdQHoldTimer?.cancel()
        cmdQHoldTimer = nil
        cmdQHoldStartedAt = nil
        cmdQHoldTargetBundleID = nil
        cmdQHoldCompleted = false
        hideHUD()
    }
    
    private func cancelCmdWHold() {
        cmdWHoldTimer?.cancel()
        cmdWHoldTimer = nil
        cmdWHoldStartedAt = nil
        cmdWHoldTargetBundleID = nil
        cmdWHoldCompleted = false
        hideHUD()
    }
    
    // MARK: - Helper Methods
    private func getKeyCode(from event: CGEvent) -> Int {
        return Int(event.getIntegerValueField(.keyboardEventKeycode))
    }
    
    private func isCmdQActive(for app: NSRunningApplication) -> Bool {
        debugLog("  🔍 Checking if Cmd+Q is active for: \(app.localizedName ?? "Unknown")")
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBar: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBar)
        guard result == .success, let menuBarElement = asAXUIElement(menuBar) else {
            debugLog("  ❌ Failed to get menu bar (result: \(result))")
            return false
        }
        
        debugLog("  ✅ Menu bar found")
        
        var children: AnyObject?
        let menuResult = AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &children)
        
        guard menuResult == .success, let items = children as? NSArray, items.count > 1 else {
            debugLog("  ❌ Failed to get menu items (result: \(menuResult), count: \((children as? NSArray)?.count ?? 0))")
            return false
        }
        
        debugLog("  ✅ Menu items found: \(items.count)")
        
        var subMenus: AnyObject?
        guard let fileMenu = asAXUIElement(items[1]) else {
            debugLog("  ❌ Failed to get File menu element")
            return false
        }
        let subMenuResult = AXUIElementCopyAttributeValue(fileMenu, kAXChildrenAttribute as CFString, &subMenus)
        
        guard subMenuResult == .success, let menus = subMenus as? [AnyObject], !menus.isEmpty else {
            debugLog("  ❌ Failed to get sub menus (result: \(subMenuResult))")
            return false
        }
        
        debugLog("  ✅ Sub menus found: \(menus.count)")
        
        var entries: AnyObject?
        guard let submenu = asAXUIElement(menus[0]) else {
            debugLog("  ❌ Failed to get submenu element")
            return false
        }
        let entriesResult = AXUIElementCopyAttributeValue(submenu, kAXChildrenAttribute as CFString, &entries)
        
        guard entriesResult == .success, let menuItems = entries as? [AnyObject], !menuItems.isEmpty else {
            debugLog("  ❌ Failed to get menu entries (result: \(entriesResult))")
            return false
        }
        
        debugLog("  ✅ Menu entries found: \(menuItems.count)")
        
        for (index, menu) in menuItems.enumerated() {
            guard let menuElement = asAXUIElement(menu) else { continue }
            var cmdChar: AnyObject?
            let cmdResult = AXUIElementCopyAttributeValue(menuElement, kAXMenuItemCmdCharAttribute as CFString, &cmdChar)
            
            if cmdResult == .success, let char = cmdChar as? String {
                debugLog("  📋 Menu item \(index): cmdChar = '\(char)'")
                if char == "Q" {
                    debugLog("  ✅ Found Cmd+Q in menu!")
                    return true
                }
            }
        }
        
        debugLog("  ❌ Cmd+Q not found in menu")
        return false
    }
    
    private func asAXUIElement(_ value: Any?) -> AXUIElement? {
        guard let value = value as CFTypeRef?, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // SAFETY: Type ID verified above.
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    
    private func showHUD(delayTime: TimeInterval, hotkey: String) {
        runOnMain {
            self.notificationManager.showHUD(
                text: "Hold \(hotkey) for \(self.delay) seconds to \(hotkey.contains("Q") ? "quit" : "close")",
                icon: "🔒",
                delayTime: delayTime
            )
        }
    }
    
    private func hideHUD() {
        runOnMain {
            self.notificationManager.dismissHUD()
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
    
    private func logAccidentalQuit() {
        internalAccidentalQuits += 1
        saveSettings()
        
        // Обновляем UI счетчик (throttling не нужен, так как событие редкое)
        DispatchQueue.main.async {
            self.accidentalQuits = self.internalAccidentalQuits
        }
        
        debugLog("📊 HotkeyBlocker: Accidental quit prevented! Total: \(internalAccidentalQuits)")
    }
    
    private func logAccidentalClose() {
        internalAccidentalCloses += 1
        saveSettings()
        
        // Обновляем UI счетчик
        DispatchQueue.main.async {
            self.accidentalCloses = self.internalAccidentalCloses
        }
        
        debugLog("📊 HotkeyBlocker: Accidental close prevented! Total: \(internalAccidentalCloses)")
    }
    
    private func terminateAppViaAppleScript(_ app: NSRunningApplication) {
        let appName = app.localizedName ?? "Unknown"
        debugLog("🔄 HotkeyBlocker: Using AppleScript fallback to terminate \(appName)")
        
        if AppleScriptCache.shared.executeQuit(for: appName) {
            debugLog("✅ HotkeyBlocker: Successfully terminated \(appName) via AppleScript")
        } else {
            debugLog("❌ HotkeyBlocker: Failed to terminate \(appName) via AppleScript")
        }
    }
}

// MARK: - Callbacks
private func keyDownCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, ptr: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let ptr = ptr else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyBlockerManager>.fromOpaque(ptr).takeUnretainedValue()
    
    // Обрабатываем отключение Event Tap системой
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.keyDownEventTap {
            manager.handleTapDisabled(type: type, tap: tap)
        }
        return nil
    }
    
    if let result = manager.handleKeyDown(event) {
        return result
    } else {
        return nil
    }
}

private func keyUpCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, ptr: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let ptr = ptr else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyBlockerManager>.fromOpaque(ptr).takeUnretainedValue()
    
    // Обрабатываем отключение Event Tap системой
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.keyUpEventTap {
            manager.handleTapDisabled(type: type, tap: tap)
        }
        return nil
    }
    
    if let result = manager.handleKeyUp(event) {
        return result
    } else {
        return nil
    }
}

// MARK: - Errors
enum QBlockerError: Error {
    case AccessibilityPermissionDenied
    case EventTapCreationFailed
    case RunLoopSourceCreationFailed
}

extension QBlockerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .AccessibilityPermissionDenied:
            return "Accessibility permissions are required for HotkeyBlocker to work"
        case .EventTapCreationFailed:
            return "Failed to create event tap for key monitoring"
        case .RunLoopSourceCreationFailed:
            return "Failed to create run loop source for event tap"
        }
    }
} 