import Foundation
import AppKit
import Carbon

// MARK: - QBlocker Manager
class QBlockerManager: ObservableObject {
    // MARK: - Properties
    @Published var isEnabled: Bool = false {
        didSet {
            if oldValue != isEnabled { // Проверяем, что значение действительно изменилось
                saveSettings()
                if isEnabled {
                    start()
                } else {
                    stop()
                }
            }
        }
    }
    @Published var accidentalQuits: Int = 0
    @Published var delay: Int = 1
    
    private var tries: Int = 0
    private var canQuit: Bool = true  // Добавляем canQuit как в оригинальном QBlocker
    
    private var eventTap: CFMachPort?
    
    private var keyDownEventTap: CFMachPort?
    private var keyUpEventTap: CFMachPort?
    private var keyDownRunLoopSource: CFRunLoopSource?
    private var keyUpRunLoopSource: CFRunLoopSource?
    
    private let notificationManager: NotificationManager
    private let exclusionManager: ExclusionManager
    
    init(notificationManager: NotificationManager, exclusionManager: ExclusionManager) {
        self.notificationManager = notificationManager
        self.exclusionManager = exclusionManager
        loadSettings()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Settings Management
    private func loadSettings() {
        let savedEnabled = UserDefaults.standard.bool(forKey: "qblocker_enabled")
        let savedAccidentalQuits = UserDefaults.standard.integer(forKey: "qblocker_accidental_quits")
        let savedDelay = UserDefaults.standard.integer(forKey: "qblocker_delay")
        
        // Устанавливаем значения напрямую, минуя didSet
        self.isEnabled = savedEnabled
        self.accidentalQuits = savedAccidentalQuits
        self.delay = savedDelay == 0 ? 1 : savedDelay // Default delay
    }
    
    func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "qblocker_enabled")
        UserDefaults.standard.set(accidentalQuits, forKey: "qblocker_accidental_quits")
        UserDefaults.standard.set(delay, forKey: "qblocker_delay")
    }
    
    // MARK: - Lifecycle
    func start() {
        guard isEnabled else { return }
        
        do {
            try startKeyMonitoring()
            print("✅ QBlocker monitoring started")
        } catch {
            print("❌ Failed to start QBlocker: \(error)")
        }
    }
    
    func startIfEnabled() throws {
        if isEnabled {
            try startKeyMonitoring()
            print("✅ QBlocker monitoring started")
        }
    }
    
    func stop() {
        stopKeyMonitoring()
        print("⏹️ QBlocker monitoring stopped")
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
            print("❌ QBlocker: Failed to create keyDown event tap - accessibility permissions may be denied")
            throw QBlockerError.AccessibilityPermissionDenied
        }
        
        guard keyUpEventTap != nil else {
            print("❌ QBlocker: Failed to create keyUp event tap - accessibility permissions may be denied")
            throw QBlockerError.AccessibilityPermissionDenied
        }
        
        // Create run loop sources
        keyDownRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyDownEventTap, 0)
        guard keyDownRunLoopSource != nil else {
            print("❌ QBlocker: Failed to create keyDown run loop source")
            throw QBlockerError.RunLoopSourceCreationFailed
        }
        
        keyUpRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyUpEventTap, 0)
        guard keyUpRunLoopSource != nil else {
            print("❌ QBlocker: Failed to create keyUp run loop source")
            throw QBlockerError.RunLoopSourceCreationFailed
        }
        
        // Add sources to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyDownRunLoopSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyUpRunLoopSource, .commonModes)
        
        print("✅ QBlocker: Event taps created and added to run loop successfully")
    }
    
    private func stopKeyMonitoring() {
        if let keyDownEventTap = keyDownEventTap {
            CGEvent.tapEnable(tap: keyDownEventTap, enable: false)
        }
        
        if let keyUpEventTap = keyUpEventTap {
            CGEvent.tapEnable(tap: keyUpEventTap, enable: false)
        }
        
        if let keyDownRunLoopSource = keyDownRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), keyDownRunLoopSource, .commonModes)
        }
        
        if let keyUpRunLoopSource = keyUpRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), keyUpRunLoopSource, .commonModes)
        }
        
        keyDownEventTap = nil
        keyUpEventTap = nil
        keyDownRunLoopSource = nil
        keyUpRunLoopSource = nil
    }
    
    // MARK: - Event Handling
    func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        
        print("🔍 QBlocker: KeyDown event received")
        print("  📋 Flags: \(flags)")
        print("  📋 Cmd: \(flags.contains(.maskCommand))")
        print("  📋 Shift: \(flags.contains(.maskShift))")
        print("  📋 Control: \(flags.contains(.maskControl))")
        
        // Check if Cmd+Q was pressed
        guard flags.contains(.maskCommand) else {
            print("  ❌ No Cmd key, passing through")
            return Unmanaged.passUnretained(event)
        }
        
        // Ignore if Shift or Control is also pressed
        guard !flags.contains(.maskShift) && !flags.contains(.maskControl) else {
            print("  ❌ Shift or Control pressed, passing through")
            return Unmanaged.passUnretained(event)
        }
        
        // Check if Q was pressed (using keycode like original QBlocker)
        let keyCode = getKeyCode(from: event)
        guard keyCode == 12 else { // 12 is the keycode for Q
            print("  ❌ Not Q key, passing through (keyCode: \(keyCode))")
            return Unmanaged.passUnretained(event)
        }
        
        print("  ✅ Cmd+Q detected!")
        
        // Check if current app is excluded from QBlocker protection
        if exclusionManager.isCurrentAppExcluded() {
            print("  ⚠️ Current app is excluded from QBlocker protection")
            return Unmanaged.passUnretained(event)
        }
        
        // Check if current app supports Cmd+Q
        guard let currentApp = NSWorkspace.shared.menuBarOwningApplication else {
            print("  ❌ No current app found")
            return Unmanaged.passUnretained(event)
        }
        
        print("  📱 Current app: \(currentApp.localizedName ?? "Unknown")")
        
        let cmdQActive = isCmdQActive(for: currentApp)
        print("  📋 Cmd+Q active for app: \(cmdQActive)")
        
        guard cmdQActive else {
            print("  ❌ Cmd+Q not active for this app, passing through")
            return Unmanaged.passUnretained(event)
        }
        
        // Check canQuit first (like original QBlocker)
        guard canQuit else {
            print("  ❌ Not allowed to quit yet")
            return nil
        }
        
        // Show HUD if we're within delay
        if tries <= delay {
            print("  📱 Showing HUD")
            showHUD(delayTime: TimeInterval(delay))
        }
        
        tries += 1
        print("🔢 QBlocker: tries = \(tries), delay = \(delay)")
        
        if tries > delay {
            print("🔓 QBlocker: Quit allowed after holding for \(delay) seconds")
            tries = 0
            canQuit = false  // Prevent rapid successive quits
            hideHUD()
            
            // Force quit the current application using AppleScript
            DispatchQueue.main.async {
                if let currentApp = NSWorkspace.shared.menuBarOwningApplication {
                    print("🚪 QBlocker: Terminating \(currentApp.localizedName ?? "Unknown")")
                    
                    let script = """
                    tell application "\(currentApp.localizedName ?? "Unknown")" to quit
                    """
                    
                    let task = Process()
                    task.launchPath = "/usr/bin/osascript"
                    task.arguments = ["-e", script]
                    
                    do {
                        try task.run()
                        print("✅ QBlocker: Successfully terminated \(currentApp.localizedName ?? "Unknown")")
                    } catch {
                        print("❌ QBlocker: Failed to terminate \(currentApp.localizedName ?? "Unknown"): \(error)")
                    }
                }
            }
            
            return nil  // Block the event since we're handling it ourselves
        }
        
        print("🔒 QBlocker: Blocking quit attempt \(tries)/\(delay)")
        return nil
    }
    
    func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        print("🔍 QBlocker: KeyUp event received")
        
        let flags = event.flags
        
        guard flags.contains(.maskCommand) else {
            return Unmanaged.passUnretained(event)
        }
        
        guard !flags.contains(.maskShift) && !flags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }
        
        // Check if Q was pressed (using keycode like original QBlocker)
        let keyCode = getKeyCode(from: event)
        guard keyCode == 12 else { // 12 is the keycode for Q
            print("  ❌ KeyUp: Not Q key, passing through (keyCode: \(keyCode))")
            return Unmanaged.passUnretained(event)
        }
        
        print("  ✅ KeyUp: Q key detected")
        
        // Log accidental quit if we didn't hold long enough
        if tries <= delay {
            print("📊 QBlocker: Accidental quit prevented! Total: \(accidentalQuits)")
            logAccidentalQuit()
        } else {
            hideHUD()
        }
        
        print("🔄 QBlocker: Resetting tries from \(tries) to 0")
        tries = 0
        canQuit = true  // Allow next quit attempt
        
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
        print("  🔍 Checking if Cmd+Q is active for: \(app.localizedName ?? "Unknown")")
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBar: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBar)
        guard result == .success, let menuBar = menuBar else {
            print("  ❌ Failed to get menu bar (result: \(result))")
            return false
        }
        
        print("  ✅ Menu bar found")
        
        var children: AnyObject?
        let menuResult = AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        
        guard menuResult == .success, let items = children as? NSArray, items.count > 1 else {
            print("  ❌ Failed to get menu items (result: \(menuResult), count: \((children as? NSArray)?.count ?? 0))")
            return false
        }
        
        print("  ✅ Menu items found: \(items.count)")
        
        // Get the submenus of the first item (Apple menu) - like original QBlocker
        var subMenus: AnyObject?
        let title = items[1] as! AXUIElement // subscript 1 is the File menu (like original)
        let subMenuResult = AXUIElementCopyAttributeValue(title, kAXChildrenAttribute as CFString, &subMenus)
        
        guard subMenuResult == .success, let menus = subMenus as? NSArray, menus.count > 0 else {
            print("  ❌ Failed to get sub menus (result: \(subMenuResult))")
            return false
        }
        
        print("  ✅ Sub menus found: \(menus.count)")
        
        // Get the entries of the submenu - like original QBlocker
        var entries: AnyObject?
        let submenu = menus[0] as! AXUIElement
        let entriesResult = AXUIElementCopyAttributeValue(submenu, kAXChildrenAttribute as CFString, &entries)
        
        guard entriesResult == .success, let menuItems = entries as? NSArray, menuItems.count > 0 else {
            print("  ❌ Failed to get menu entries (result: \(entriesResult))")
            return false
        }
        
        print("  ✅ Menu entries found: \(menuItems.count)")
        
        // Check each menu item for Cmd+Q - like original QBlocker
        for (index, menu) in menuItems.enumerated() {
            var cmdChar: AnyObject?
            let cmdResult = AXUIElementCopyAttributeValue(menu as! AXUIElement, kAXMenuItemCmdCharAttribute as CFString, &cmdChar)
            
            if cmdResult == .success, let char = cmdChar as? String {
                print("  📋 Menu item \(index): cmdChar = '\(char)'")
                if char == "Q" {
                    print("  ✅ Found Cmd+Q in menu!")
                    return true
                }
            }
        }
        
        print("  ❌ Cmd+Q not found in menu")
        return false
    }
    
    private func showHUD(delayTime: TimeInterval) {
        // Show HUD using NotificationManager
        DispatchQueue.main.async {
            self.notificationManager.showHUD(
                text: "Hold Cmd+Q for \(self.delay) seconds to quit",
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
        accidentalQuits += 1
        saveSettings()
        print("📊 QBlocker: Accidental quit prevented! Total: \(accidentalQuits)")
    }
}

// MARK: - Callbacks
private func keyDownCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, ptr: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let ptr = ptr else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<QBlockerManager>.fromOpaque(ptr).takeUnretainedValue()
    
    if let result = manager.handleKeyDown(event) {
        return result
    } else {
        return nil
    }
}

private func keyUpCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, ptr: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let ptr = ptr else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<QBlockerManager>.fromOpaque(ptr).takeUnretainedValue()
    
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
            return "Accessibility permissions are required for QBlocker to work"
        case .EventTapCreationFailed:
            return "Failed to create event tap for key monitoring"
        case .RunLoopSourceCreationFailed:
            return "Failed to create run loop source for event tap"
        }
    }
} 