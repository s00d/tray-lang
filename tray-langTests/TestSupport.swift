import AppKit
@testable import tray_lang

enum Layouts {
    static let abc = SystemKeyboardLayouts.abcLayoutID
    static let russianMac = "com.apple.keylayout.Russian"
    static let russianPC = "com.apple.keylayout.RussianWin"
    static let ukrainianPC = "com.apple.keylayout.Ukrainian-PC"
    static let german = "com.apple.keylayout.German"

    /// Every layout offered as a built-in profile.
    static let common = SystemKeyboardLayouts.commonLayoutIDs

    static func transformer(_ target: String, enabled: [String]? = nil) -> TextTransformer {
        TextTransformer(profile: .system(target: target), enabledLayouts: { enabled ?? [abc, target] })
    }

    static func resolved(_ target: String) -> TextTransformer.ResolvedProfile {
        TextTransformer.resolve(.system(target: target), enabledLayouts: [])!
    }

    /// All characters a layout types (plain + Shift) on the printable keys.
    static func characters(_ layoutID: String) -> [String] {
        guard let table = SystemKeyboardLayouts.keyTable(layoutID: layoutID) else { return [] }
        var seen = Set<String>()
        return SystemKeyboardLayouts.printableKeyCodes
            .flatMap { [table[$0]?.plain ?? "", table[$0]?.shifted ?? ""] }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Where a key ends after two conversions when two keys type the same character.
    static func roundTripAlias(_ char: String, _ resolved: TextTransformer.ResolvedProfile) -> String {
        if let forward = resolved.forward[char], let back = resolved.inverse[forward] { return back }
        return char
    }
}

/// A text field in some app, as seen through Accessibility and the clipboard.
/// Behaviour flags reproduce real apps that broke conversion before.
final class FakeTextApp: SelectionDriver {
    enum AXBehavior {
        /// Native Cocoa: AX read/write works and updates the value.
        case native
        /// Electron & co.: AX write says success but changes nothing.
        case liesAboutWrite
        /// AX write works, but the selection keeps reporting the old text (stale cache, e.g. Chromium).
        case staleSelection
        /// AX write works, value is not readable, selection collapses afterwards.
        case writeWithoutValue
        /// No AX text at all; only the clipboard works.
        case none
        /// The app is busy: the write is accepted but shows up only `after` seconds later (Telegram under load).
        case appliesLate(after: TimeInterval)
        /// The AX call times out on our side, yet the app performs the write.
        case timesOutButApplies
    }

    var bundleID: String?
    var axBehavior: AXBehavior
    var text: String
    var selection: Range<String.Index>?
    /// VS Code-style: Cmd+C without a selection copies the current line plus newline.
    var copiesLineWithoutSelection = false
    var terminalLine: String?

    private(set) var pasteCount = 0
    private(set) var axWriteCount = 0
    private var pendingWrite: (text: String, landsAt: Date)?
    private(set) var clearedTerminalCharacters: Int?
    private var pendingPasteCompletions: [() -> Void] = []

    init(text: String, selected: String? = nil, bundleID: String? = "com.example.editor", axBehavior: AXBehavior = .native) {
        self.text = text
        self.bundleID = bundleID
        self.axBehavior = axBehavior
        if let selected {
            selection = text.range(of: selected)
        } else if !text.isEmpty {
            selection = text.startIndex..<text.endIndex
        }
    }

    var selectedText: String? {
        guard let selection, !selection.isEmpty else { return nil }
        return String(text[selection])
    }

    private var staleSelectedText: String?

    private func replaceSelection(with newText: String) {
        let range = selection ?? text.endIndex..<text.endIndex
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        text.replaceSubrange(range, with: newText)
        let lower = text.index(text.startIndex, offsetBy: start)
        selection = lower..<text.index(lower, offsetBy: newText.count)
    }

    // MARK: SelectionDriver

    var frontmostBundleID: String? { bundleID }

    func accessibilitySelectedText() -> String? {
        switch axBehavior {
        case .none: return nil
        case .staleSelection: return staleSelectedText ?? selectedText
        case .writeWithoutValue: return axWriteCount > 0 ? nil : selectedText
        default: return selectedText
        }
    }

    func accessibilityFocusedValue() -> String? {
        if let pending = pendingWrite, Date() >= pending.landsAt {
            pendingWrite = nil
            replaceSelection(with: pending.text)
        }
        switch axBehavior {
        case .none, .writeWithoutValue: return nil
        default: return text
        }
    }

    func accessibilityReplaceSelection(with newText: String) -> AXWriteResult {
        switch axBehavior {
        case .none:
            return .failed
        case .liesAboutWrite:
            axWriteCount += 1
            return .done
        case let .appliesLate(delay):
            axWriteCount += 1
            pendingWrite = (newText, Date().addingTimeInterval(delay))
            return .done
        case .timesOutButApplies:
            axWriteCount += 1
            replaceSelection(with: newText)
            return .uncertain
        case .staleSelection:
            staleSelectedText = selectedText
            fallthrough
        default:
            axWriteCount += 1
            replaceSelection(with: newText)
            return .done
        }
    }

    func copySelectionViaClipboard() -> String? {
        if let selectedText { return selectedText }
        guard copiesLineWithoutSelection else { return nil }
        let lineStart = text[..<(selection?.lowerBound ?? text.endIndex)].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
        return String(text[lineStart..<lineEnd]) + "\n"
    }

    func pasteViaClipboard(_ newText: String, completion: @escaping () -> Void) {
        pasteCount += 1
        replaceSelection(with: newText)
        pendingPasteCompletions.append(completion)
    }

    /// The real driver restores the clipboard after a delay; tests decide when that happens.
    func finishPendingPastes() {
        let completions = pendingPasteCompletions
        pendingPasteCompletions.removeAll()
        completions.forEach { $0() }
    }

    func terminalCommandLine() -> String? { terminalLine }

    func clearTerminalLine(characterCount: Int) {
        clearedTerminalCharacters = characterCount
        text = ""
        selection = nil
    }

    func wait(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
