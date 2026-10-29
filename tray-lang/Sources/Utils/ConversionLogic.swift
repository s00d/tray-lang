import Foundation

/// Time budgets for clipboard-based conversion (mode 3).
/// Kept in one place so tests can catch accidental latency regressions.
enum ClipboardConversionTiming {
    /// Max wait for Cmd/Shift/Opt/Ctrl to clear before synthetic Cmd+C/V.
    static let modifiersTimeout: TimeInterval = 0.2

    /// Max wait for pasteboard changeCount after Cmd+C.
    static let pasteboardChangeTimeout: TimeInterval = 0.25

    /// Delay before restoring original clipboard after paste, when the field can't be read to see the paste land.
    static let clipboardRestoreDelay: TimeInterval = 0.3

    /// Longest wait for a paste to show up in a readable field before restoring the clipboard anyway.
    static let pasteLandTimeout: TimeInterval = 1.5

    /// Worst-case wall time for mode-3 waits when modifiers are already released
    /// (pasteboard timeout + restore delay). Does not include user still holding the hotkey.
    static var maxPassiveMode3Wait: TimeInterval {
        pasteboardChangeTimeout + clipboardRestoreDelay
    }

    /// Hard ceiling — if someone reintroduces stacked 0.5s waits, tests fail.
    static let maxAllowedPassiveMode3Wait: TimeInterval = 0.6
}

/// Pure helpers for clipboard marker capture used by mode 3.
enum ClipboardMarkerLogic {
    /// After Cmd+C, decide whether the pasteboard holds selected text.
    static func capturedText(marker: String, pasteboardString: String?) -> String? {
        guard let pasteboardString, !pasteboardString.isEmpty, pasteboardString != marker else {
            return nil
        }
        return pasteboardString
    }

    /// Editors like VS Code copy the whole current line (with its newline) when nothing is selected.
    static func looksLikeWholeLineCopy(_ text: String) -> Bool {
        text.hasSuffix("\n") && !text.dropLast().contains("\n")
    }

    /// Whether restore should be skipped because something else changed the pasteboard.
    static func shouldSkipRestore(currentChangeCount: Int, writtenChangeCount: Int) -> Bool {
        currentChangeCount != writtenChangeCount
    }
}

/// Hold-to-quit duration checks (real seconds, not key-repeat counts).
enum HoldDurationLogic {
    static func hasHeldLongEnough(startedAt: Date, now: Date, requiredSeconds: TimeInterval) -> Bool {
        now.timeIntervalSince(startedAt) >= requiredSeconds
    }

    /// Autorepeat must not start a new hold.
    static func shouldBeginHold(isAlreadyHolding: Bool, isAutorepeat: Bool) -> Bool {
        !isAlreadyHolding && !isAutorepeat
    }
}
