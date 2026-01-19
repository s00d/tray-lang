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
    
    private var cmdQTries: Int = 0
    private var cmdWTries: Int = 0
    private var canQuit: Bool = true
    private var canClose: Bool = true
    
    private var eventTap: CFMachPort?
    
    // Используются в callback функциях, поэтому не могут быть private
    var keyDownEventTap: CFMachPort?
    var keyUpEventTap: CFMachPort?
    private var keyDownRunLoopSource: CFRunLoopSource?
    private var keyUpRunLoopSource: CFRunLoopSource?
    
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
    
    init(notificationManager: NotificationManager, exclusionManager: ExclusionManager) {
        self.notificationManager = notificationManager
        self.exclusionManager = exclusionManager
        // 2. УБИРАЕМ loadSettings() из init. AppCoordinator сам задаст начальные значения.
        // Загружаем только статистику и задержку
        self.internalAccidentalQuits = UserDefaults.standard.integer(forKey: "qblocker_accidental_quits")
        self.internalAccidentalCloses = UserDefaults.standard.integer(forKey: "wblocker_accidental_closes")
        self.accidentalQuits = internalAccidentalQuits
        self.accidentalCloses = internalAccidentalCloses
        let savedDelay = UserDefaults.standard.integer(forKey: "qblocker_delay")
        self.delay = savedDelay == 0 ? 1 : savedDelay
        
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
        UserDefaults.standard.set(isCmdQEnabled, forKey: "qblocker_enabled")
        UserDefaults.standard.set(isCmdWEnabled, forKey: "wblocker_enabled")
        UserDefaults.standard.set(internalAccidentalQuits, forKey: "qblocker_accidental_quits")
        UserDefaults.standard.set(internalAccidentalCloses, forKey: "wblocker_accidental_closes")
        UserDefaults.standard.set(delay, forKey: "qblocker_delay")
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
                    self.isCmdQEnabled = false
                    self.isCmdWEnabled = false
                }
            }
        }
        
        monitoringThread?.name = "com.traylang.keyboardMonitor"
        monitoringThread?.qualityOfService = .userInteractive
        monitoringThread?.start()
        
        debugLog("✅ HotkeyBlocker monitoring thread started")
    }
    
    func startIfEnabled() throws {
        if isCmdQEnabled || isCmdWEnabled {
            try startKeyMonitoring()
            debugLog("✅ HotkeyBlocker monitoring started")
        }
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
        
        // Сбрасываем состояние после остановки
        DispatchQueue.main.async {
            self.isCmdQEnabled = false
            self.isCmdWEnabled = false
        }
    }
    
    func forceStop() {
        stopKeyMonitoring()
        debugLog("⏹️ HotkeyBlocker monitoring force stopped")
        
        // Принудительно сбрасываем состояние
        DispatchQueue.main.async {
            self.isCmdQEnabled = false
            self.isCmdWEnabled = false
            self.saveSettings()
        }
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
    
    func syncState() {
        debugLog("🔄 Syncing HotkeyBlocker state...")
        debugLog("  📋 isCmdQEnabled: \(isCmdQEnabled)")
        debugLog("  📋 isCmdWEnabled: \(isCmdWEnabled)")
        debugLog("  📋 isMonitoring: \(isMonitoring)")
        
        // Синхронизируем состояние с фактическим мониторингом
        if !isMonitoring && (isCmdQEnabled || isCmdWEnabled) {
            debugLog("  ⚠️ State mismatch detected, resetting...")
            DispatchQueue.main.async {
                self.isCmdQEnabled = false
                self.isCmdWEnabled = false
                self.saveSettings()
            }
        }
    }
    
    // MARK: - Key Monitoring
    private func startKeyMonitoring() throws {
        // Key Down Event Tap
        keyDownEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: keyDownCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        // Key Up Event Tap
        keyUpEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyUp.rawValue),
            callback: keyUpCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        // Check if event taps were created successfully
        guard keyDownEventTap != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyDown event tap - accessibility permissions may be denied")
            throw QBlockerError.AccessibilityPermissionDenied
        }
        
        guard keyUpEventTap != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyUp event tap - accessibility permissions may be denied")
            throw QBlockerError.AccessibilityPermissionDenied
        }
        
        // Create run loop sources
        keyDownRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyDownEventTap, 0)
        guard keyDownRunLoopSource != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyDown run loop source")
            throw QBlockerError.RunLoopSourceCreationFailed
        }
        
        keyUpRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyUpEventTap, 0)
        guard keyUpRunLoopSource != nil else {
            debugLog("❌ HotkeyBlocker: Failed to create keyUp run loop source")
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
        }
        
        if let keyUpEventTap = keyUpEventTap {
            CGEvent.tapEnable(tap: keyUpEventTap, enable: false)
        }
        
        if let keyDownRunLoopSource = keyDownRunLoopSource, let runLoop = monitoringRunLoop {
            CFRunLoopRemoveSource(runLoop, keyDownRunLoopSource, .commonModes)
        }
        
        if let keyUpRunLoopSource = keyUpRunLoopSource, let runLoop = monitoringRunLoop {
            CFRunLoopRemoveSource(runLoop, keyUpRunLoopSource, .commonModes)
        }
        
        keyDownEventTap = nil
        keyUpEventTap = nil
        keyDownRunLoopSource = nil
        keyUpRunLoopSource = nil
    }
    
    // MARK: - Event Handling
    func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = getKeyCode(from: event)
        
        debugLog("🔍 HotkeyBlocker: KeyDown event received")
        debugLog("  📋 Flags: \(flags)")
        debugLog("  📋 Cmd: \(flags.contains(.maskCommand))")
        debugLog("  📋 Shift: \(flags.contains(.maskShift))")
        debugLog("  📋 Control: \(flags.contains(.maskControl))")
        debugLog("  📋 KeyCode: \(keyCode)")
        
        // Check if Cmd key was pressed
        guard flags.contains(.maskCommand) else {
            debugLog("  ❌ No Cmd key, passing through")
            return Unmanaged.passUnretained(event)
        }
        
        // Ignore if Shift or Control is also pressed
        guard !flags.contains(.maskShift) && !flags.contains(.maskControl) else {
            debugLog("  ❌ Shift or Control pressed, passing through")
            return Unmanaged.passUnretained(event)
        }
        
        // Handle Cmd+Q
        if keyCode == 12 && isCmdQEnabled { // 12 is the keycode for Q
            return handleCmdQDown(event)
        }
        
        // Handle Cmd+W
        if keyCode == 13 && isCmdWEnabled { // 13 is the keycode for W
            return handleCmdWDown(event)
        }
        
        debugLog("  ❌ Not Q or W key, passing through")
        return Unmanaged.passUnretained(event)
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
        
        self.currentAppBundleID = bundleID
        
        // Сбрасываем счетчики
        cmdQTries = 0
        cmdWTries = 0
        
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
    
    private func handleCmdQDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        debugLog("  ✅ Cmd+Q detected!")
        
        // Быстрая проверка исключений по строке (без API вызовов)
        if let bundleID = currentAppBundleID, exclusionManager.isAppExcluded(bundleID: bundleID) {
            debugLog("  ⚠️ Current app is excluded from protection")
            return Unmanaged.passUnretained(event)
        }
        
        // Читаем кэшированное значение (мгновенно)
        if !currentAppSupportsCmdQ {
            debugLog("  ❌ Cmd+Q not active for this app (cached), passing through")
            return Unmanaged.passUnretained(event)
        }
        
        // Check canQuit first
        guard canQuit else {
            debugLog("  ❌ Not allowed to quit yet")
            return nil
        }
        
        // Show HUD if we're within delay
        if cmdQTries <= delay {
            debugLog("  📱 Showing HUD")
            showHUD(delayTime: TimeInterval(delay), hotkey: "Cmd+Q")
        } else {
            // Hide HUD if we're past the delay
            hideHUD()
        }
        
        cmdQTries += 1
        debugLog("🔢 HotkeyBlocker: cmdQTries = \(cmdQTries), delay = \(delay)")
        
        if cmdQTries > delay {
            debugLog("🔓 HotkeyBlocker: Quit allowed after holding for \(delay) seconds")
            cmdQTries = 0
            canQuit = false  // Prevent rapid successive quits
            hideHUD()
            
            // Force quit the current application using NSRunningApplication
            DispatchQueue.main.async {
                if let currentApp = NSWorkspace.shared.menuBarOwningApplication {
                    debugLog("🚪 HotkeyBlocker: Terminating \(currentApp.localizedName ?? "Unknown")")
                    
                    // Используем нативный API для завершения приложения
                    if let runningApp = NSRunningApplication(processIdentifier: currentApp.processIdentifier) {
                        if runningApp.terminate() {
                            debugLog("✅ HotkeyBlocker: Successfully terminated \(currentApp.localizedName ?? "Unknown")")
                        } else {
                            debugLog("❌ HotkeyBlocker: Failed to terminate, trying force terminate")
                            // Если terminate не сработал, пробуем force terminate
                            if runningApp.forceTerminate() {
                                debugLog("✅ HotkeyBlocker: Successfully force terminated \(currentApp.localizedName ?? "Unknown")")
                            } else {
                                debugLog("❌ HotkeyBlocker: Failed to force terminate, falling back to AppleScript")
                                // Запасной вариант - AppleScript
                                self.terminateAppViaAppleScript(currentApp)
                            }
                        }
                    } else {
                        debugLog("❌ HotkeyBlocker: Could not create NSRunningApplication, falling back to AppleScript")
                        self.terminateAppViaAppleScript(currentApp)
                    }
                }
            }
            
            return nil  // Block the event since we're handling it ourselves
        }
        
        debugLog("🔒 HotkeyBlocker: Blocking quit attempt \(cmdQTries)/\(delay)")
        return nil
    }
    
    private func handleCmdWDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        debugLog("  ✅ Cmd+W detected!")
        
        // Check if current app is excluded from protection
        if exclusionManager.isCurrentAppExcluded() {
            debugLog("  ⚠️ Current app is excluded from protection")
            return Unmanaged.passUnretained(event)
        }
        
        // Check canClose first
        guard canClose else {
            debugLog("  ❌ Not allowed to close yet")
            return nil
        }
        
        // Show HUD if we're within delay
        if cmdWTries <= delay {
            debugLog("  📱 Showing HUD")
            showHUD(delayTime: TimeInterval(delay), hotkey: "Cmd+W")
        } else {
            // Hide HUD if we're past the delay
            hideHUD()
        }
        
        cmdWTries += 1
        debugLog("🔢 HotkeyBlocker: cmdWTries = \(cmdWTries), delay = \(delay)")
        
        if cmdWTries > delay {
            debugLog("🔓 HotkeyBlocker: Close allowed after holding for \(delay) seconds")
            cmdWTries = 0
            canClose = false  // Prevent rapid successive closes
            hideHUD()
            
            // Send Cmd+W event to close the window
            DispatchQueue.main.async {
                debugLog("🚪 HotkeyBlocker: Sending Cmd+W to close window")
                // Create and post a new Cmd+W event
                if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true) {
                    newEvent.flags = .maskCommand
                    newEvent.post(tap: .cghidEventTap)
                }
            }
            
            return nil  // Block the original event since we're handling it ourselves
        }
        
        debugLog("🔒 HotkeyBlocker: Blocking close attempt \(cmdWTries)/\(delay)")
        return nil
    }
    
    func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        debugLog("🔍 HotkeyBlocker: KeyUp event received")
        
        let flags = event.flags
        let keyCode = getKeyCode(from: event)
        
        guard flags.contains(.maskCommand) else {
            return Unmanaged.passUnretained(event)
        }
        
        guard !flags.contains(.maskShift) && !flags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }
        
        // Handle Cmd+Q key up
        if keyCode == 12 && isCmdQEnabled {
            return handleCmdQUp(event)
        }
        
        // Handle Cmd+W key up
        if keyCode == 13 && isCmdWEnabled {
            return handleCmdWUp(event)
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleCmdQUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        debugLog("  ✅ KeyUp: Q key detected")
        
        // Log accidental quit if we didn't hold long enough
        if cmdQTries <= delay {
            debugLog("📊 HotkeyBlocker: Accidental quit prevented! Total: \(accidentalQuits)")
            logAccidentalQuit()
        } else {
            hideHUD()
        }
        
        debugLog("🔄 HotkeyBlocker: Resetting cmdQTries from \(cmdQTries) to 0")
        cmdQTries = 0
        canQuit = true  // Allow next quit attempt
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleCmdWUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        debugLog("  ✅ KeyUp: W key detected")
        
        // Log accidental close if we didn't hold long enough
        if cmdWTries <= delay {
            debugLog("📊 HotkeyBlocker: Accidental close prevented! Total: \(accidentalCloses)")
            logAccidentalClose()
        } else {
            hideHUD()
        }
        
        debugLog("🔄 HotkeyBlocker: Resetting cmdWTries from \(cmdWTries) to 0")
        cmdWTries = 0
        canClose = true  // Allow next close attempt
        
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - Helper Methods
    private func getKeyValue(from event: CGEvent) -> String? {
        return NSEvent(cgEvent: event)?.charactersIgnoringModifiers
    }
    
    private func getKeyCode(from event: CGEvent) -> Int {
        return Int(event.getIntegerValueField(.keyboardEventKeycode))
    }
    
    private func isCmdQActive(for app: NSRunningApplication) -> Bool {
        debugLog("  🔍 Checking if Cmd+Q is active for: \(app.localizedName ?? "Unknown")")
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBar: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBar)
        guard result == .success, let menuBar = menuBar else {
            debugLog("  ❌ Failed to get menu bar (result: \(result))")
            return false
        }
        
        debugLog("  ✅ Menu bar found")
        
        var children: AnyObject?
        let menuResult = AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        
        guard menuResult == .success, let items = children as? NSArray, items.count > 1 else {
            debugLog("  ❌ Failed to get menu items (result: \(menuResult), count: \((children as? NSArray)?.count ?? 0))")
            return false
        }
        
        debugLog("  ✅ Menu items found: \(items.count)")
        
        // Get the submenus of the first item (Apple menu) - like original QBlocker
        var subMenus: AnyObject?
        let title = items[1] as! AXUIElement // subscript 1 is the File menu (like original)
        let subMenuResult = AXUIElementCopyAttributeValue(title, kAXChildrenAttribute as CFString, &subMenus)
        
        guard subMenuResult == .success, let menus = subMenus as? NSArray, menus.count > 0 else {
            debugLog("  ❌ Failed to get sub menus (result: \(subMenuResult))")
            return false
        }
        
        debugLog("  ✅ Sub menus found: \(menus.count)")
        
        // Get the entries of the submenu - like original QBlocker
        var entries: AnyObject?
        let submenu = menus[0] as! AXUIElement
        let entriesResult = AXUIElementCopyAttributeValue(submenu, kAXChildrenAttribute as CFString, &entries)
        
        guard entriesResult == .success, let menuItems = entries as? NSArray, menuItems.count > 0 else {
            debugLog("  ❌ Failed to get menu entries (result: \(entriesResult))")
            return false
        }
        
        debugLog("  ✅ Menu entries found: \(menuItems.count)")
        
        // Check each menu item for Cmd+Q - like original QBlocker
        for (index, menu) in menuItems.enumerated() {
            var cmdChar: AnyObject?
            let cmdResult = AXUIElementCopyAttributeValue(menu as! AXUIElement, kAXMenuItemCmdCharAttribute as CFString, &cmdChar)
            
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
    
    private func showHUD(delayTime: TimeInterval, hotkey: String) {
        // Show HUD using NotificationManager
        DispatchQueue.main.async {
            self.notificationManager.showHUD(
                text: "Hold \(hotkey) for \(self.delay) seconds to \(hotkey.contains("Q") ? "quit" : "close")",
                icon: "🔒",
                delayTime: delayTime
            )
        }
    }
    
    private func hideHUD() {
        DispatchQueue.main.async {
            self.notificationManager.dismissHUD()
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