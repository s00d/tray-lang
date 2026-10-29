import Foundation
import Testing
@testable import tray_lang

/// The hotkey flow against fake apps. The key invariant: converted text is inserted exactly once,
/// and nothing is inserted when there is no selection.
@MainActor
@Suite(.serialized)
struct TextReplacementTests {
    private let transformer = Layouts.transformer(Layouts.russianMac)
    private let layouts = KeyboardLayoutManager()

    private func run(_ app: FakeTextApp, action: ProcessingAction = .changeLayout) -> TextProcessingManager {
        let manager = TextProcessingManager(
            textTransformer: transformer,
            keyboardLayoutManager: layouts,
            spellCheckManager: SpellCheckManager(),
            notificationManager: NotificationManager(),
            driver: app,
            switchesLayout: false,
            replaceVerificationTimeout: 0.2
        )
        manager.processSelectedText(action: action)
        app.finishPendingPastes()
        return manager
    }

    // MARK: Accessibility path

    @Test func nativeFieldReplacesThroughAccessibilityOnly() {
        let app = FakeTextApp(text: "ghbdtn", axBehavior: .native)
        let manager = run(app)
        #expect(app.text == "привет")
        #expect(app.axWriteCount == 1)
        #expect(app.pasteCount == 0)
        #expect(!manager.isProcessing)
    }

    @Test func onlyTheSelectionChanges() {
        let app = FakeTextApp(text: "say ghbdtn now", selected: "ghbdtn")
        _ = run(app)
        #expect(app.text == "say привет now")
    }

    @Test func surroundingWhitespaceInTheSelectionIsKept() {
        let app = FakeTextApp(text: "  ghbdtn\n")
        _ = run(app)
        #expect(app.text == "  привет\n")
    }

    @Test func appThatLiesAboutAXWriteGetsOnePaste() {
        let app = FakeTextApp(text: "ghbdtn", bundleID: "com.tinyspeck.slackmacgap", axBehavior: .liesAboutWrite)
        _ = run(app)
        #expect(app.text == "привет")
        #expect(app.pasteCount == 1)
    }

    /// Chromium-style stale AXSelectedText after a successful write used to trigger a second insert by paste.
    @Test func staleSelectionAfterSuccessfulWriteDoesNotPasteAgain() {
        let app = FakeTextApp(text: "ghbdtn", bundleID: "com.google.Chrome", axBehavior: .staleSelection)
        _ = run(app)
        #expect(app.text == "привет")
        #expect(app.pasteCount == 0)
    }

    @Test func writeWithUnreadableValueIsTrusted() {
        let app = FakeTextApp(text: "ghbdtn", axBehavior: .writeWithoutValue)
        _ = run(app)
        #expect(app.text == "привет")
        #expect(app.pasteCount == 0)
    }

    // MARK: Slow apps (Telegram under load) — the reported double insert

    /// Telegram busy for 0.4 s: the write lands late. Giving up early and pasting inserted the text twice.
    @Test func lateAXWriteIsWaitedForNotPastedOver() {
        let app = FakeTextApp(text: "ghbdtn", bundleID: "ru.keepcoder.Telegram", axBehavior: .appliesLate(after: 0.4))
        let manager = TextProcessingManager(
            textTransformer: transformer,
            keyboardLayoutManager: layouts,
            spellCheckManager: SpellCheckManager(),
            notificationManager: NotificationManager(),
            driver: app,
            switchesLayout: false
        )
        manager.processSelectedText(action: .changeLayout)
        app.finishPendingPastes()
        #expect(app.text == "привет")
        #expect(app.pasteCount == 0, "paste on top of a late AX write inserts the text twice")
    }

    /// Our AX call timed out but the app still performed it: never paste after an uncertain write.
    @Test func timedOutAXWriteIsNotFollowedByPaste() {
        let app = FakeTextApp(text: "ghbdtn", bundleID: "ru.keepcoder.Telegram", axBehavior: .timesOutButApplies)
        _ = run(app)
        #expect(app.text == "привет")
        #expect(app.pasteCount == 0)
    }

    /// An app that ignores AX writes costs the wait once; after that it goes straight to paste.
    @Test func appThatIgnoresAXWritesIsRememberedForTheSession() {
        let manager = TextProcessingManager(
            textTransformer: transformer,
            keyboardLayoutManager: layouts,
            spellCheckManager: SpellCheckManager(),
            notificationManager: NotificationManager(),
            driver: FakeTextApp(text: ""),
            switchesLayout: false,
            replaceVerificationTimeout: 0.05
        )
        let first = FakeTextApp(text: "ghbdtn", bundleID: "com.example.electron", axBehavior: .liesAboutWrite)
        manager.driverForTesting = first
        manager.processSelectedText(action: .changeLayout)
        first.finishPendingPastes()
        #expect(first.text == "привет")
        #expect(first.axWriteCount == 1)
        #expect(first.pasteCount == 1)

        let second = FakeTextApp(text: "ghbdtn", bundleID: "com.example.electron", axBehavior: .liesAboutWrite)
        manager.driverForTesting = second
        manager.processSelectedText(action: .changeLayout)
        second.finishPendingPastes()
        #expect(second.text == "привет")
        #expect(second.axWriteCount == 0, "known to ignore AX writes: paste directly, no wait")
        #expect(second.pasteCount == 1)
    }

    @Test func menuPressThatTimedOutCountsAsDelivered() {
        #expect(MenuAction.wasDelivered(.success))
        #expect(MenuAction.wasDelivered(.cannotComplete), "a timed-out press still runs in the app; adding ⌘V doubles the paste")
        #expect(!MenuAction.wasDelivered(.actionUnsupported))
        #expect(!MenuAction.wasDelivered(.invalidUIElement))
        #expect(!MenuAction.wasDelivered(.apiDisabled))
    }

    @Test func axWriteResultFromAXError() {
        #expect(AXWriteResult(.success) == .done)
        #expect(AXWriteResult(.cannotComplete) == .uncertain)
        #expect(AXWriteResult(.attributeUnsupported) == .failed)
        #expect(AXWriteResult(.invalidUIElement) == .failed)
    }

    // MARK: Clipboard path

    @Test func appWithoutAXTextUsesClipboardOnce() {
        let app = FakeTextApp(text: "руддщ", axBehavior: .none)
        _ = run(app)
        #expect(app.text == "hello")
        #expect(app.pasteCount == 1)
    }

    @Test func nothingSelectedDoesNothing() {
        let app = FakeTextApp(text: "ghbdtn", axBehavior: .none)
        app.selection = nil
        let manager = run(app)
        #expect(app.text == "ghbdtn")
        #expect(app.pasteCount == 0)
        #expect(!manager.isProcessing)
    }

    /// VS Code copies the whole line when nothing is selected — pasting it back would duplicate the line.
    @Test func lineCopyEditorWithoutSelectionDoesNothing() {
        let app = FakeTextApp(text: "ghbdtn", bundleID: "com.microsoft.VSCode", axBehavior: .none)
        app.selection = app.text.endIndex..<app.text.endIndex
        app.copiesLineWithoutSelection = true
        _ = run(app)
        #expect(app.text == "ghbdtn")
        #expect(app.pasteCount == 0)
    }

    @Test func lineCopyEditorWithRealSelectionConverts() {
        let app = FakeTextApp(text: "ghbdtn vbh", selected: "vbh", bundleID: "com.microsoft.VSCode", axBehavior: .none)
        app.copiesLineWithoutSelection = true
        _ = run(app)
        #expect(app.text == "ghbdtn мир")
        #expect(app.pasteCount == 1)
    }

    @Test func vsCodeIsNotTreatedAsATerminal() {
        #expect(!ConversionAppRouting.usesTerminalPath(bundleID: "com.microsoft.VSCode"))
        #expect(ConversionAppRouting.copiesWholeLineWithoutSelection(bundleID: "com.microsoft.VSCode"))
        #expect(ConversionAppRouting.copiesWholeLineWithoutSelection(bundleID: "com.jetbrains.intellij"))
        #expect(!ConversionAppRouting.copiesWholeLineWithoutSelection(bundleID: "com.apple.TextEdit"))
    }

    // MARK: Terminal path

    @Test func terminalReplacesTheCommandLine() {
        let app = FakeTextApp(text: "пше ыефегы", bundleID: "com.apple.Terminal", axBehavior: .none)
        app.terminalLine = "пше ыефегы"
        _ = run(app)
        #expect(app.clearedTerminalCharacters == 10)
        #expect(app.text == "git status")
        #expect(app.pasteCount == 1)
    }

    @Test func unreadableTerminalDoesNothing() {
        let app = FakeTextApp(text: "", bundleID: "com.googlecode.iterm2", axBehavior: .none)
        let manager = run(app)
        #expect(app.pasteCount == 0)
        #expect(app.clearedTerminalCharacters == nil)
        #expect(!manager.isProcessing)
    }

    // MARK: Flow control

    @Test func unchangedTextIsNotWritten() {
        let app = FakeTextApp(text: "123 456")
        _ = run(app)
        #expect(app.axWriteCount == 0)
        #expect(app.pasteCount == 0)
    }

    @Test func secondHotkeyWhilePasteIsPendingIsIgnored() {
        let app = FakeTextApp(text: "ghbdtn", axBehavior: .none)
        let manager = TextProcessingManager(
            textTransformer: transformer,
            keyboardLayoutManager: layouts,
            spellCheckManager: SpellCheckManager(),
            notificationManager: NotificationManager(),
            driver: app,
            switchesLayout: false
        )
        manager.processSelectedText(action: .changeLayout)
        #expect(manager.isProcessing)
        manager.processSelectedText(action: .changeLayout)
        #expect(app.pasteCount == 1, "a repeated hotkey must not paste again")
        app.finishPendingPastes()
        #expect(!manager.isProcessing)
        #expect(app.text == "привет")
    }

    @Test func pressingTwiceConvertsBack() {
        let app = FakeTextApp(text: "фыва ghjjk")
        _ = run(app)
        #expect(app.text == "asdf проол")
        _ = run(app)
        #expect(app.text == "фыва ghjjk")
    }

    @Test func spellCheckUsesTheSameReplaceFlow() {
        let app = FakeTextApp(text: "I recieve it", axBehavior: .native)
        _ = run(app, action: .fixSpelling)
        #expect(app.text == "I receive it")
        #expect(app.pasteCount == 0)
    }

    // MARK: Pure decisions

    @Test func verificationRules() {
        typealias V = ReplaceVerification
        #expect(V.outcome(original: "a", valueBefore: "xa", valueAfter: "xa", selectionAfter: "a") == .notApplied)
        #expect(V.outcome(original: "a", valueBefore: "xa", valueAfter: "xb", selectionAfter: "a") == .applied, "stale selection, value changed")
        #expect(V.outcome(original: "a", valueBefore: nil, valueAfter: nil, selectionAfter: "a") == .notApplied)
        #expect(V.outcome(original: "a", valueBefore: nil, valueAfter: nil, selectionAfter: nil) == .applied)
        #expect(V.outcome(original: "a", valueBefore: nil, valueAfter: nil, selectionAfter: "b") == .applied)
        #expect(V.outcome(original: "a", valueBefore: "xa", valueAfter: nil, selectionAfter: "b") == .applied)
    }

    @Test func wholeLineCopyDetection() {
        #expect(ClipboardMarkerLogic.looksLikeWholeLineCopy("let x = 1\n"))
        #expect(!ClipboardMarkerLogic.looksLikeWholeLineCopy("let x = 1"))
        #expect(!ClipboardMarkerLogic.looksLikeWholeLineCopy("a\nb\n"))
        #expect(!ClipboardMarkerLogic.looksLikeWholeLineCopy(""))
    }
}
