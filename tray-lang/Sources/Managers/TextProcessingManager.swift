import Foundation
import AppKit
import ApplicationServices

enum ProcessingAction {
    case changeLayout
    case fixSpelling
}

class TextProcessingManager: ObservableObject {
    private struct ClipboardSnapshot {
        let items: [NSPasteboardItem]
        let changeCount: Int
    }
    
    private let textTransformer: TextTransformer
    private let keyboardLayoutManager: KeyboardLayoutManager
    private let spellCheckManager: SpellCheckManager
    private let notificationManager: NotificationManager
    
    private var isProcessing = false
    
    init(
        textTransformer: TextTransformer,
        keyboardLayoutManager: KeyboardLayoutManager,
        spellCheckManager: SpellCheckManager,
        notificationManager: NotificationManager
    ) {
        self.textTransformer = textTransformer
        self.keyboardLayoutManager = keyboardLayoutManager
        self.spellCheckManager = spellCheckManager
        self.notificationManager = notificationManager
    }
    
    // MARK: - Main Logic
    
    func processSelectedText(action: ProcessingAction) {
        guard !isProcessing else {
            debugLog("⚠️ Already processing, ignoring duplicate hotkey")
            return
        }
        isProcessing = true
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmostApp.bundleIdentifier else {
            finishProcessing()
            return
        }
        
        debugLog("🚀 APP: \(frontmostApp.localizedName ?? "?") | Bundle ID: \(bundleID)")
        
        // manualDeepCopy reads pasteboard data eagerly; lazy/promised types may not round-trip.
        let snapshot = captureClipboardSnapshot()
        
        if ConversionAppRouting.usesTerminalPath(bundleID: bundleID) {
            handleTerminalProcessing(app: frontmostApp, action: action, snapshot: snapshot)
            return
        }
        
        attemptAccessibilityStrategy(action: action, snapshot: snapshot)
    }
    
    // MARK: - Terminal Logic
    
    private func handleTerminalProcessing(
        app: NSRunningApplication,
        action: ProcessingAction,
        snapshot: ClipboardSnapshot
    ) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        guard let focused = asAXUIElement(getAXAttribute(appElement, kAXFocusedUIElementAttribute as String)),
              let fullText = getAXAttribute(focused, kAXValueAttribute as String) as? String,
              !fullText.isEmpty else {
            debugLog("❌ Терминал: Не удалось прочитать текст через Accessibility")
            finishProcessing()
            return
        }
        
        let lines = fullText.components(separatedBy: .newlines)
        guard let lastLine = lines.reversed().first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            finishProcessing()
            return
        }
        
        let commandText = TerminalPromptExtractor.extractCommand(from: lastLine)
        if commandText.isEmpty {
            finishProcessing()
            return
        }
        
        let transformedText: String
        switch action {
        case .changeLayout:
            transformedText = textTransformer.transformText(commandText)
        case .fixSpelling:
            transformedText = spellCheckManager.fixText(commandText)
        }
        if transformedText == commandText {
            finishProcessing()
            return
        }
        
        debugLog("🔄 Терминал: '\(commandText)' -> '\(transformedText)'")
        
        clearTerminalLine(length: commandText.count)
        replaceTextForTerminal(transformedText, snapshot: snapshot)
        if action == .changeLayout {
            switchToNextLayout()
        }
    }
    
    private func clearTerminalLine(length: Int) {
        let safeLength = min(length, 300)
        sendCtrlKey(14)
        usleep(20000)
        
        for _ in 0..<(safeLength + 2) {
            sendKey(51)
            usleep(1000)
        }
        usleep(50000)
    }
    
    // MARK: - Pasteboard Strategies
    
    private func replaceTextForTerminal(_ newText: String, snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(newText, forType: .string)
        let writtenChangeCount = pasteboard.changeCount
        
        performCmdV()
        
        scheduleClipboardRestore(snapshot: snapshot, writtenChangeCount: writtenChangeCount)
    }
    
    private func replaceTextViaPasteboardStrategy(_ newText: String, snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .init("org.nspasteboard.TransientType")], owner: nil)
        pasteboard.setString(newText, forType: .string)
        let writtenChangeCount = pasteboard.changeCount
        
        performCmdV()
        
        scheduleClipboardRestore(snapshot: snapshot, writtenChangeCount: writtenChangeCount)
    }
    
    private func scheduleClipboardRestore(snapshot: ClipboardSnapshot, writtenChangeCount: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + ClipboardConversionTiming.clipboardRestoreDelay) { [weak self] in
            debugLog("📋 Restoring clipboard...")
            self?.restoreClipboard(snapshot, ifUnchangedSince: writtenChangeCount)
            self?.finishProcessing()
        }
    }
    
    // MARK: - Standard Logic
    
    private func attemptAccessibilityStrategy(action: ProcessingAction, snapshot: ClipboardSnapshot) {
        if let selectedText = getSelectedText() {
            debugLog("✅ Text retrieved via Accessibility")
            processTextAndReplace(selectedText, useAccessibilityReplace: true, action: action, snapshot: snapshot)
            return
        }
        
        debugLog("ℹ️ Accessibility failed, trying Marker Strategy via Clipboard")
        
        do {
            if let text = try getSelectedTextViaMarkerStrategy(snapshot: snapshot) {
                debugLog("✅ Text retrieved via Marker Strategy")
                processTextAndReplace(text, useAccessibilityReplace: false, action: action, snapshot: snapshot)
            } else {
                debugLog("⚠️ No text selected or app blocked Cmd+C")
                finishProcessing()
            }
        } catch {
            debugLog("❌ Marker Strategy error: \(error)")
            finishProcessing()
        }
    }
    
    private func processTextAndReplace(
        _ text: String,
        useAccessibilityReplace: Bool,
        action: ProcessingAction,
        snapshot: ClipboardSnapshot
    ) {
        debugLog("📝 Processing text: '\(text.prefix(30))...' (length: \(text.count))")
        
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        debugLog("🧹 After cleanup: '\(cleanText.prefix(30))...' (length: \(cleanText.count))")
        
        let transformed: String
        switch action {
        case .changeLayout:
            transformed = textTransformer.transformText(cleanText)
        case .fixSpelling:
            transformed = spellCheckManager.fixText(cleanText)
        }
        debugLog("🔄 After transform: '\(transformed.prefix(30))...' (length: \(transformed.count))")
        
        if transformed == cleanText {
            debugLog("ℹ️ Text unchanged after transformation, skipping")
            finishProcessing()
            return
        }
        
        if useAccessibilityReplace {
            debugLog("🔧 Attempting Accessibility replace...")
            if replaceTextViaAccessibility(transformed) {
                debugLog("✅ Accessibility replace returned success")
                
                usleep(20000)
                
                if let verifiedText = getSelectedText() {
                    debugLog("🔍 Verification: got '\(verifiedText.prefix(20))...'")
                    
                    if verifiedText == transformed {
                        debugLog("✅ Verification PASSED: text actually replaced")
                        if action == .changeLayout {
                            switchToNextLayout()
                        }
                        finishProcessing()
                        return
                    }
                    
                    debugLog("⚠️ Verification FAILED: AX lied, text not replaced")
                    debugLog("📋 Falling back to Pasteboard strategy")
                } else {
                    debugLog("✅ Assuming AX replace succeeded (native app behavior)")
                    if action == .changeLayout {
                        switchToNextLayout()
                    }
                    finishProcessing()
                    return
                }
            } else {
                debugLog("⚠️ AX Replace returned failure, using Pasteboard")
            }
        }
        
        debugLog("📋 Using Pasteboard strategy...")
        replaceTextViaPasteboardStrategy(transformed, snapshot: snapshot)
        if action == .changeLayout {
            switchToNextLayout()
        }
    }
    
    // MARK: - Marker Strategy
    
    private func getSelectedTextViaMarkerStrategy(snapshot: ClipboardSnapshot) throws -> String? {
        let pasteboard = NSPasteboard.general
        
        let marker = UUID().uuidString
        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        let markerChangeCount = pasteboard.changeCount
        
        debugLog("🎯 Marker Strategy: Set UUID marker")
        
        performCmdC()
        
        guard PasteboardHelper.waitForPasteboardChange(
            originalCount: markerChangeCount,
            timeout: ClipboardConversionTiming.pasteboardChangeTimeout
        ) else {
            debugLog("⚠️ Marker Strategy: pasteboard did not change after Cmd+C")
            restoreClipboard(snapshot)
            return nil
        }
        
        guard let currentContent = ClipboardMarkerLogic.capturedText(
            marker: marker,
            pasteboardString: pasteboard.string(forType: .string)
        ) else {
            debugLog("⚠️ Marker intact after copy. Nothing selected or Copy blocked.")
            restoreClipboard(snapshot)
            return nil
        }
        
        debugLog("🎯 Marker Strategy: Text captured")
        return currentContent
    }
    
    // MARK: - Clipboard Helpers
    
    private func captureClipboardSnapshot() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        return ClipboardSnapshot(
            items: pasteboard.pasteboardItems?.map { $0.manualDeepCopy() } ?? [],
            changeCount: pasteboard.changeCount
        )
    }
    
    private func restoreClipboard(_ snapshot: ClipboardSnapshot, ifUnchangedSince changeCount: Int? = nil) {
        let pasteboard = NSPasteboard.general
        
        if let changeCount, ClipboardMarkerLogic.shouldSkipRestore(
            currentChangeCount: pasteboard.changeCount,
            writtenChangeCount: changeCount
        ) {
            debugLog("📋 Skipping clipboard restore — pasteboard changed externally")
            return
        }
        
        pasteboard.clearContents()
        if !snapshot.items.isEmpty {
            pasteboard.writeObjects(snapshot.items)
        }
    }
    
    private func finishProcessing() {
        isProcessing = false
        DispatchQueue.main.async { [weak self] in
            self?.notificationManager.dismissHUD()
        }
    }
    
    /// Wait until Cmd/Shift/Opt/Ctrl are released so synthetic Cmd+C/V is not mangled.
    /// Polls quickly and exits as soon as flags are clear (typical ~0–50ms after key-up).
    private func waitForModifiersReleased(
        timeout: TimeInterval = ClipboardConversionTiming.modifiersTimeout
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.isDisjoint(with: modifierMask) {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
        }
    }
    
    // MARK: - Input Simulation
    
    private func performCmdC() {
        waitForModifiersReleased()
        
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return }
        
        down.flags = .maskCommand
        up.flags = .maskCommand
        
        down.post(tap: .cghidEventTap)
        usleep(2000)
        up.post(tap: .cghidEventTap)
    }
    
    private func performCmdV() {
        waitForModifiersReleased()
        
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        
        down.flags = .maskCommand
        up.flags = .maskCommand
        
        down.post(tap: .cghidEventTap)
        usleep(2000)
        up.post(tap: .cghidEventTap)
    }
    
    private func sendKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    private func sendCtrlKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        
        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    // MARK: - Utilities
    
    private func switchToNextLayout() {
        keyboardLayoutManager.switchToNextLayout()
    }
    
    private func getAXAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.1)
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return error == .success ? result : nil
    }
    
    private func asAXUIElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    
    private func getSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = asAXUIElement(getAXAttribute(element, kAXFocusedUIElementAttribute as String)) else { return nil }
        
        if let text = getAXAttribute(focused, kAXSelectedTextAttribute as String) as? String, !text.isEmpty {
            return text
        }
        return nil
    }
    
    private func replaceTextViaAccessibility(_ newText: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = asAXUIElement(getAXAttribute(element, kAXFocusedUIElementAttribute as String)) else { return false }
        return AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, newText as CFString) == .success
    }
}
