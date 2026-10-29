import Foundation
import AppKit
import ApplicationServices

/// Real `SelectionDriver`: Accessibility first, then the app's own Edit menu, then synthetic ⌘C/⌘V.
/// Menu actions and clipboard rules follow SelectedTextKit (Easydict): https://github.com/tisfeng/SelectedTextKit
final class SystemSelectionDriver: SelectionDriver {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    // MARK: Accessibility

    func accessibilitySelectedText() -> String? {
        guard let focused = AX.focusedElement() else { return nil }
        if let text = AX.attribute(focused, kAXSelectedTextAttribute) as? String, !text.isEmpty {
            return text
        }
        // WebKit / Chromium often leave AXSelectedText empty but expose the selection as a text-marker range.
        guard let range = AX.attribute(focused, "AXSelectedTextMarkerRange") else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(focused, "AXStringForTextMarkerRange" as CFString, range, &result)
        guard status == .success, let text = result as? String, !text.isEmpty else { return nil }
        return text
    }

    func accessibilityFocusedValue() -> String? {
        AX.focusedElement().flatMap { AX.attribute($0, kAXValueAttribute) as? String }
    }

    func accessibilityReplaceSelection(with text: String) -> AXWriteResult {
        guard let focused = AX.focusedElement() else { return .failed }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return .failed }
        // A busy app answers late; give the write more time than a read, and treat a timeout as "may apply".
        AXUIElementSetMessagingTimeout(focused, AX.actionTimeout)
        return AXWriteResult(AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFString))
    }

    // MARK: Clipboard

    func copySelectionViaClipboard() -> String? {
        let copyItem = MenuAction.find(.copy)
        // A disabled Edit › Copy means nothing is selected: stop instead of copying something else.
        if copyItem?.isEnabled == false {
            return nil
        }

        let backup = ClipboardBackup(pasteboard)
        let marker = UUID().uuidString
        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        let markerChangeCount = pasteboard.changeCount

        if copyItem.map({ MenuAction.wasDelivered($0.press()) }) != true {
            KeySynthesizer.press(keyCode: 8, flags: .maskCommand)
        }

        let copied = PasteboardHelper.waitForString(
            changedFrom: markerChangeCount,
            timeout: ClipboardConversionTiming.pasteboardChangeTimeout,
            pasteboard: pasteboard
        )
        backup.restore()
        return ClipboardMarkerLogic.capturedText(marker: marker, pasteboardString: copied)
    }

    func pasteViaClipboard(_ text: String, completion: @escaping () -> Void) {
        let valueBefore = accessibilityFocusedValue()
        let backup = ClipboardBackup(pasteboard)
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
        pasteboard.setString(text, forType: .string)
        let writtenChangeCount = pasteboard.changeCount

        // A press that timed out still runs in the app: sending ⌘V as well would paste twice.
        let menuItem = MenuAction.find(.paste)
        let pastedViaMenu = menuItem.map { $0.isEnabled && MenuAction.wasDelivered($0.press()) } ?? false
        if !pastedViaMenu {
            KeySynthesizer.press(keyCode: 9, flags: .maskCommand)
        }

        // Restore only after the app has read the clipboard: when the field is readable, wait for it to change
        // (a busy app may take a second); otherwise fall back to a fixed delay.
        let restore: () -> Void = { [pasteboard] in
            if ClipboardMarkerLogic.shouldSkipRestore(currentChangeCount: pasteboard.changeCount, writtenChangeCount: writtenChangeCount) {
                debugLog("📋 Clipboard changed externally, not restoring")
            } else {
                backup.restore()
            }
            completion()
        }
        guard let valueBefore else {
            DispatchQueue.main.asyncAfter(deadline: .now() + ClipboardConversionTiming.clipboardRestoreDelay, execute: restore)
            return
        }
        let deadline = Date().addingTimeInterval(ClipboardConversionTiming.pasteLandTimeout)
        func check() {
            if accessibilityFocusedValue() != valueBefore || Date() >= deadline {
                // Small grace period: some apps read the clipboard again right after inserting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: restore)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: check)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: check)
    }

    // MARK: Terminal

    func terminalCommandLine() -> String? {
        guard let focused = AX.focusedElement(),
              let fullText = AX.attribute(focused, kAXValueAttribute) as? String,
              let lastLine = fullText.components(separatedBy: .newlines)
                .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        return TerminalPromptExtractor.extractCommand(from: lastLine)
    }

    /// ⌃E (end of line) then ⌃U (kill to line start): clears the command line in bash, zsh and fish.
    func clearTerminalLine(characterCount: Int) {
        KeySynthesizer.press(keyCode: 14, flags: .maskControl)
        KeySynthesizer.press(keyCode: 32, flags: .maskControl)
    }

    func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(seconds))
    }
}

// MARK: - Clipboard backup

/// Deep copy of the clipboard (lazy / promised types do not survive `clearContents()`).
struct ClipboardBackup {
    private let pasteboard: NSPasteboard
    private let items: [NSPasteboardItem]

    init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        items = pasteboard.pasteboardItems?.map { $0.manualDeepCopy() } ?? []
    }

    func restore() {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

// MARK: - Accessibility helpers

enum AX {
    static let messagingTimeout: Float = 0.1
    /// Writes and presses: a busy app can take longer to answer than a read.
    static let actionTimeout: Float = 0.5

    static func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return element(appElement, kAXFocusedUIElementAttribute)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }

    static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func children(_ parent: AXUIElement) -> [AXUIElement] {
        attribute(parent, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}

/// An Edit-menu item of the frontmost app, pressed through Accessibility.
/// Works regardless of keyboard layout or held modifiers, and its enabled state tells whether Copy is possible.
struct MenuAction {
    enum Kind: String {
        case copy = "copy:"
        case paste = "paste:"

        var commandCharacter: String { self == .copy ? "C" : "V" }
    }

    let element: AXUIElement

    var isEnabled: Bool {
        (AX.attribute(element, kAXEnabledAttribute) as? Bool) ?? true
    }

    func press() -> AXError {
        AXUIElementSetMessagingTimeout(element, AX.actionTimeout)
        return AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// `.cannotComplete` means our call timed out, not that the app refused: it performs the press anyway.
    static func wasDelivered(_ result: AXError) -> Bool {
        result == .success || result == .cannotComplete
    }

    static func find(_ kind: Kind) -> MenuAction? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let menuBar = AX.element(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute) else {
            return nil
        }
        let topItems = AX.children(menuBar)
        // Edit is usually the 4th top-level menu (Apple, App, File, Edit); search outward from there.
        let order = [3, 2, 4, 1, 5, 0] + Array(6..<max(6, topItems.count))
        for index in order where index < topItems.count {
            guard let menu = AX.children(topItems[index]).first else { continue }
            if let match = AX.children(menu).first(where: { matches($0, kind) }) {
                return MenuAction(element: match)
            }
        }
        return nil
    }

    private static func matches(_ item: AXUIElement, _ kind: Kind) -> Bool {
        if AX.attribute(item, kAXIdentifierAttribute) as? String == kind.rawValue { return true }
        // Apps without identifiers: ⌘C / ⌘V with no extra modifiers (0 means ⌘ only).
        return AX.attribute(item, kAXMenuItemCmdCharAttribute) as? String == kind.commandCharacter
            && AX.attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int == 0
    }
}

// MARK: - Synthetic keys

enum KeySynthesizer {
    static func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        if flags.contains(.maskCommand) {
            waitForModifiersReleased()
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// The user may still hold the hotkey's modifiers; a synthetic ⌘C would become ⌘⇧C etc.
    private static func waitForModifiersReleased(timeout: TimeInterval = ClipboardConversionTiming.modifiersTimeout) {
        let deadline = Date().addingTimeInterval(timeout)
        let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        while Date() < deadline {
            if CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: mask) { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
        }
    }
}
