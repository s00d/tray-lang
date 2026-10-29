import Foundation
import AppKit

enum ProcessingAction {
    case changeLayout
    case fixSpelling
}

/// Everything the conversion flow needs from the system. `SystemSelectionDriver` is the real one;
/// tests plug in fakes that behave like specific apps (AX that lies, stale selection, line-copy editors).
protocol SelectionDriver: AnyObject {
    var frontmostBundleID: String? { get }
    /// Selected text via Accessibility, nil when the app does not expose it.
    func accessibilitySelectedText() -> String?
    /// Whole value of the focused element via Accessibility, used to verify a replace.
    func accessibilityFocusedValue() -> String?
    func accessibilityReplaceSelection(with text: String) -> AXWriteResult
    /// Copies the selection through the clipboard; nil when nothing is selected.
    func copySelectionViaClipboard() -> String?
    /// Puts `text` on the clipboard, pastes it and restores the clipboard; `completion` runs after restore.
    func pasteViaClipboard(_ text: String, completion: @escaping () -> Void)
    /// Last command line of a terminal (prompt stripped), nil when unreadable.
    func terminalCommandLine() -> String?
    func clearTerminalLine(characterCount: Int)
    /// Lets the target app process events (AX writes can apply asynchronously).
    func wait(_ seconds: TimeInterval)
}

/// Outcome of writing the selection through Accessibility.
enum AXWriteResult: Equatable {
    /// The app accepted the write.
    case done
    /// The write was not delivered (not settable, no element…): safe to use another way.
    case failed
    /// Our call timed out; a busy app may still perform it. Never insert the text a second way.
    case uncertain

    init(_ error: AXError) {
        switch error {
        case .success: self = .done
        case .cannotComplete: self = .uncertain
        default: self = .failed
        }
    }
}

enum ReplaceVerification {
    enum Outcome: Equatable {
        case applied
        case notApplied
    }

    /// Decide whether an AX replace that reported success really happened.
    /// Falling back to paste when the text *was* replaced inserts it twice, so anything
    /// other than clear evidence of "nothing changed" counts as applied.
    static func outcome(
        original: String,
        valueBefore: String?,
        valueAfter: String?,
        selectionAfter: String?
    ) -> Outcome {
        if let valueBefore, let valueAfter {
            return valueBefore == valueAfter ? .notApplied : .applied
        }
        return selectionAfter == original ? .notApplied : .applied
    }
}

final class TextProcessingManager {
    private let textTransformer: TextTransformer
    private let keyboardLayoutManager: KeyboardLayoutManager
    private let spellCheckManager: SpellCheckManager
    private let notificationManager: NotificationManager
    private var driver: SelectionDriver
    private let switchesLayout: Bool
    /// How long to wait for an AX write to show up before deciding the app ignored it.
    /// Long enough for a busy app (Telegram, Electron) to catch up; we leave as soon as it lands.
    private let replaceVerificationTimeout: TimeInterval
    /// Apps that accepted an AX write but never applied it: they get the clipboard path directly.
    private var appsIgnoringAXWrites: Set<String> = []

    private(set) var isProcessing = false

    var driverForTesting: SelectionDriver {
        get { driver }
        set { driver = newValue }
    }

    init(
        textTransformer: TextTransformer,
        keyboardLayoutManager: KeyboardLayoutManager,
        spellCheckManager: SpellCheckManager,
        notificationManager: NotificationManager,
        driver: SelectionDriver = SystemSelectionDriver(),
        switchesLayout: Bool = !ProcessRuntime.isRunningUnderTests,
        replaceVerificationTimeout: TimeInterval = 1.0
    ) {
        self.replaceVerificationTimeout = replaceVerificationTimeout
        self.textTransformer = textTransformer
        self.keyboardLayoutManager = keyboardLayoutManager
        self.spellCheckManager = spellCheckManager
        self.notificationManager = notificationManager
        self.driver = driver
        self.switchesLayout = switchesLayout
    }

    // MARK: - Main flow

    func processSelectedText(action: ProcessingAction) {
        guard !isProcessing else {
            debugLog("⚠️ Already processing, ignoring duplicate hotkey")
            return
        }
        isProcessing = true

        let bundleID = driver.frontmostBundleID
        debugLog("🚀 Bundle ID: \(bundleID ?? "?")")

        if let bundleID, ConversionAppRouting.usesTerminalPath(bundleID: bundleID) {
            processTerminal(action: action)
            return
        }

        if let selected = driver.accessibilitySelectedText(), !selected.isEmpty {
            replace(selected, action: action, selectedViaAccessibility: true, bundleID: bundleID)
            return
        }

        guard let copied = driver.copySelectionViaClipboard(), !copied.isEmpty else {
            debugLog("⚠️ No selection")
            finishProcessing()
            return
        }
        if let bundleID, ConversionAppRouting.copiesWholeLineWithoutSelection(bundleID: bundleID),
           ClipboardMarkerLogic.looksLikeWholeLineCopy(copied) {
            // VS Code & co. copy the current line when nothing is selected; pasting would duplicate it.
            debugLog("⚠️ Line copy without selection — skipping")
            finishProcessing()
            return
        }
        replace(copied, action: action, selectedViaAccessibility: false, bundleID: bundleID)
    }

    private func convert(_ text: String, action: ProcessingAction) -> (text: String, switchTo: String?) {
        switch action {
        case .fixSpelling:
            return (spellCheckManager.fixText(text), nil)
        case .changeLayout:
            let conversion = textTransformer.convert(text, typedInLayoutID: keyboardLayoutManager.currentLayoutID)
            let layout = conversion.endsOn.flatMap { textTransformer.layoutIDToSelect(after: $0) }
            return (conversion.text, layout)
        }
    }

    private func replace(_ original: String, action: ProcessingAction, selectedViaAccessibility: Bool, bundleID: String?) {
        let (converted, layoutID) = convert(original, action: action)
        guard converted != original else {
            debugLog("ℹ️ Text unchanged, skipping")
            finishProcessing()
            return
        }

        if selectedViaAccessibility, replaceViaAccessibility(original: original, converted: converted, bundleID: bundleID) {
            selectLayout(layoutID)
            finishProcessing()
            return
        }

        driver.pasteViaClipboard(converted) { [weak self] in
            self?.finishProcessing()
        }
        selectLayout(layoutID)
    }

    /// True when the AX write landed or may still land — the clipboard path must not run then,
    /// or a busy app ends up with the text twice.
    private func replaceViaAccessibility(original: String, converted: String, bundleID: String?) -> Bool {
        if let bundleID, appsIgnoringAXWrites.contains(bundleID) {
            return false
        }
        let valueBefore = driver.accessibilityFocusedValue()
        switch driver.accessibilityReplaceSelection(with: converted) {
        case .failed:
            debugLog("⚠️ AX replace not delivered, using paste")
            return false
        case .uncertain:
            debugLog("⚠️ AX replace timed out; assuming the app applies it, no paste")
            return true
        case .done:
            break
        }

        let deadline = Date().addingTimeInterval(replaceVerificationTimeout)
        repeat {
            let outcome = ReplaceVerification.outcome(
                original: original,
                valueBefore: valueBefore,
                valueAfter: driver.accessibilityFocusedValue(),
                selectionAfter: driver.accessibilitySelectedText()
            )
            if outcome == .applied {
                debugLog("✅ AX replace applied")
                return true
            }
            driver.wait(0.02)
        } while Date() < deadline

        debugLog("⚠️ AX write accepted but never applied; this app gets the clipboard path from now on")
        if let bundleID {
            appsIgnoringAXWrites.insert(bundleID)
        }
        return false
    }

    // MARK: - Terminal

    private func processTerminal(action: ProcessingAction) {
        guard let command = driver.terminalCommandLine(), !command.isEmpty else {
            debugLog("❌ Terminal: command line unreadable")
            finishProcessing()
            return
        }
        let (converted, layoutID) = convert(command, action: action)
        guard converted != command else {
            finishProcessing()
            return
        }
        debugLog("🔄 Terminal: '\(command)' -> '\(converted)'")
        driver.clearTerminalLine(characterCount: command.count)
        driver.pasteViaClipboard(converted) { [weak self] in
            self?.finishProcessing()
        }
        selectLayout(layoutID)
    }

    // MARK: - Helpers

    private func selectLayout(_ layoutID: String?) {
        guard switchesLayout, let layoutID else { return }
        if !keyboardLayoutManager.switchToLayout(id: layoutID) {
            debugLog("⚠️ Could not select layout \(layoutID)")
        }
    }

    private func finishProcessing() {
        isProcessing = false
        notificationManager.dismissHUD()
    }
}
