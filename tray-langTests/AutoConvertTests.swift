import Foundation
import Testing
@testable import tray_lang

/// Auto-convert while typing: decisions are made by a pure engine fed with key events,
/// so every case runs without touching the real keyboard.
@MainActor
@Suite(.enabled(if: Dictionaries.russianAndEnglish, "needs the Russian and English system dictionaries"))
struct AutoConvertTests {
    /// Real dictionaries for the two languages involved.
    private let validator = SpellCheckWordValidator()
    private let transformer = Layouts.transformer(Layouts.russianMac)

    private func engine() -> AutoConvertEngine {
        AutoConvertEngine(transformer: transformer, validator: validator)
    }

    private func key(_ characters: String) -> AutoConvertEngine.Key {
        .init(keyCode: 0, characters: characters)
    }

    private let space = AutoConvertEngine.Key(keyCode: 49, characters: " ")
    private let backspace = AutoConvertEngine.Key(keyCode: 51, characters: "\u{7F}")

    /// Types `text` (letters and spaces), returns the action after the last key.
    private func type(_ text: String, into engine: inout AutoConvertEngine, layout: String = Layouts.abc) -> AutoConvertEngine.Action {
        var last = AutoConvertEngine.Action.none
        for char in text {
            last = engine.handle(char == " " ? space : key(String(char)), currentLayoutID: layout)
        }
        return last
    }

    // MARK: Converts

    @Test func wrongLayoutWordIsReplacedOnSpace() {
        var engine = engine()
        let action = type("ghbdtn ", into: &engine)
        #expect(action == .replace(deleteCount: 7, text: "привет ", switchTo: .toTarget))
    }

    @Test func russianLayoutTypingEnglishIsReplaced() {
        var engine = engine()
        let action = type("руддщ ", into: &engine, layout: Layouts.russianMac)
        #expect(action == .replace(deleteCount: 6, text: "hello ", switchTo: .toSource))
    }

    @Test func shortCommonWordsConvert() {
        var engine = engine()
        #expect(type("yt ", into: &engine) == .replace(deleteCount: 3, text: "не ", switchTo: .toTarget))
        #expect(type("rfr ", into: &engine) == .replace(deleteCount: 4, text: "как ", switchTo: .toTarget))
    }

    @Test func punctuationTypedOnWrongLayoutComesAlong() {
        var engine = engine()
        // Shift+6 is "," on Russian (Mac)
        #expect(type("ghbdtn^ ", into: &engine) == .replace(deleteCount: 8, text: "привет, ", switchTo: .toTarget))
    }

    // MARK: Leaves alone

    @Test func correctWordsAreLeftAlone() {
        var engine = engine()
        #expect(type("hello ", into: &engine) == .none)
        #expect(type("привет ", into: &engine, layout: Layouts.russianMac) == .none)
    }

    @Test func gibberishInBothLanguagesIsLeftAlone() {
        var engine = engine()
        #expect(type("qzxjv ", into: &engine) == .none, "neither qzxjv nor йячол is a word")
    }

    @Test func codeLikeTokensAreLeftAlone() {
        var engine = engine()
        for token in ["ghbdtn2 ", "ghb_dtn ", "a@b ", "ghb/dtn ", "x "] {
            #expect(type(token, into: &engine) == .none, "\(token)")
        }
    }

    @Test func nothingHappensWithoutSpace() {
        var engine = engine()
        #expect(type("ghbdtn", into: &engine) == .none)
    }

    // MARK: Word buffer

    @Test func backspaceEditsTheWord() {
        var engine = engine()
        _ = type("ghbdtnn", into: &engine)
        #expect(engine.handle(backspace, currentLayoutID: Layouts.abc) == .none)
        #expect(type(" ", into: &engine) == .replace(deleteCount: 7, text: "привет ", switchTo: .toTarget))
    }

    @Test func shortcutsArrowsAndClicksResetTheWord() {
        var engine = engine()
        _ = type("ghb", into: &engine)
        _ = engine.handle(.init(keyCode: 123, characters: ""), currentLayoutID: Layouts.abc) // ←
        #expect(type("dtn ", into: &engine) == .none, "only 'dtn' was seen after the arrow")

        _ = type("ghb", into: &engine)
        _ = engine.handle(.init(keyCode: 8, characters: "c", hasCommandOrControl: true), currentLayoutID: Layouts.abc)
        #expect(type("dtn ", into: &engine) == .none)

        _ = type("ghb", into: &engine)
        engine.reset()
        #expect(type("dtn ", into: &engine) == .none)
    }

    @Test func returnDoesNotTriggerConversion() {
        var engine = engine()
        _ = type("ghbdtn", into: &engine)
        #expect(engine.handle(.init(keyCode: 36, characters: "\r"), currentLayoutID: Layouts.abc) == .none, "Return may send a message")
        #expect(type(" ", into: &engine) == .none)
    }

    @Test func ownSyntheticEventsAreIgnored() {
        var engine = engine()
        _ = type("ghbdtn", into: &engine)
        #expect(engine.handle(.init(keyCode: 49, characters: " ", isSynthetic: true), currentLayoutID: Layouts.abc) == .none)
        #expect(type(" ", into: &engine) != .none, "synthetic space neither converted nor reset the word")
    }

    // MARK: Undo

    @Test func deleteRightAfterConversionUndoesIt() {
        var engine = engine()
        _ = type("ghbdtn ", into: &engine)
        let undo = engine.handle(backspace, currentLayoutID: Layouts.russianMac)
        // The user's Delete removed the space; remove "привет" and retype what they typed.
        #expect(undo == .undo(deleteCount: 6, text: "ghbdtn ", switchTo: .toSource))
    }

    @Test func undoneWordIsNotConvertedAgain() {
        var engine = engine()
        _ = type("ghbdtn ", into: &engine)
        _ = engine.handle(backspace, currentLayoutID: Layouts.russianMac)
        #expect(type("ghbdtn ", into: &engine) == .none)
    }

    @Test func undoOnlyRightAfterConversion() {
        var engine = engine()
        _ = type("ghbdtn ", into: &engine)
        _ = type("f", into: &engine, layout: Layouts.russianMac)
        #expect(engine.handle(backspace, currentLayoutID: Layouts.russianMac) == .none)
    }

    // MARK: Profiles

    @Test func sameScriptProfilesNeverAutoConvert() {
        var engine = AutoConvertEngine(transformer: Layouts.transformer(Layouts.german), validator: validator)
        #expect(type("Zeit ", into: &engine) == .none)
    }

    @Test func emptyProfileDoesNothing() {
        var engine = AutoConvertEngine(
            transformer: TextTransformer(profile: .auto, enabledLayouts: { [Layouts.abc] }),
            validator: validator
        )
        #expect(type("ghbdtn ", into: &engine) == .none)
    }

    // MARK: Cost

    /// ~12k keystrokes, a dictionary check on every Space: must stay far below typing speed.
    @Test func engineCostPerKeyIsNegligible() {
        var engine = engine()
        let words = ["hello", "ghbdtn", "world", "rfr", "ltkf", "привет", "test", "yt"]
        let text = (0..<2_000).map { words[$0 % words.count] }.joined(separator: " ") + " "
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = type(text, into: &engine)
        }
        let perKey = elapsed / text.count
        #expect(perKey < .microseconds(200), "per key: \(perKey)")
    }

}

/// Parts of auto-convert that need no dictionaries.
struct AutoConvertOutputTests {

    @Test func codeEditorsAndTerminalsAreSkippedByDefault() {
        #expect(AutoConvertManager.isSkippedByDefault(bundleID: "com.apple.Terminal"))
        #expect(AutoConvertManager.isSkippedByDefault(bundleID: "com.microsoft.VSCode"))
        #expect(AutoConvertManager.isSkippedByDefault(bundleID: "com.apple.dt.Xcode"))
        #expect(AutoConvertManager.isSkippedByDefault(bundleID: "com.jetbrains.intellij"))
        #expect(!AutoConvertManager.isSkippedByDefault(bundleID: "com.apple.TextEdit"))
        #expect(!AutoConvertManager.isSkippedByDefault(bundleID: "com.tinyspeck.slackmacgap"))
    }

    @Test func unicodeTextIsSplitIntoEventSizedChunks() {
        let text = String(repeating: "привет ", count: 10) + "👨‍👩‍👧"
        let chunks = KeystrokeOutput.chunks(text)
        #expect(chunks.allSatisfy { $0.count <= 20 })
        #expect(String(utf16CodeUnits: chunks.flatMap { $0 }, count: chunks.reduce(0) { $0 + $1.count }) == text)
        // A surrogate pair is never split between two events.
        for chunk in chunks.dropLast() {
            #expect(!UTF16.isLeadSurrogate(chunk.last!))
        }
    }

    @Test func soundsShipWithTheAppAndAreTiny() throws {
        for name in ["switch", "switch-back"] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "wav"))
            let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            #expect(size < 8_000, "\(name) should stay a tiny UI sound")
        }
    }
}
