import AppKit
import Testing
@testable import tray_lang

/// Random and unusual input: the converter must never lose or duplicate text, and two passes must restore it.
struct ConversionStressTests {
    /// Deterministic generator so a failure reproduces.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func randomText(from words: [[String]], using rng: inout SeededGenerator) -> String {
        let separators = [" ", " ", " ", "  ", "\n", "\t"]
        return (0..<Int.random(in: 1...8, using: &rng)).map { _ in
            let alphabet = words.randomElement(using: &rng)!
            return (0..<Int.random(in: 1...10, using: &rng)).map { _ in alphabet.randomElement(using: &rng)! }.joined()
        }.joined(separator: separators.randomElement(using: &rng)!)
    }

    /// Words made only of one side's keys round-trip exactly, whatever mixes and punctuation they contain.
    @Test(arguments: [Layouts.russianMac, Layouts.russianPC, Layouts.ukrainianPC])
    func randomMixedTextRoundTrips(layoutID: String) {
        let transformer = Layouts.transformer(layoutID)
        let resolved = Layouts.resolved(layoutID)
        // Per-side alphabets without the ISO key, so no key is an alias.
        let latin = Layouts.characters(Layouts.abc).filter { $0 != "§" && $0 != "±" && resolved.forward[$0] != nil }
        let letters = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
        let target = latin.compactMap { resolved.forward[$0] }
        let targetLetters = letters.compactMap { resolved.forward[$0] }

        var rng = SeededGenerator(state: 0xC0FFEE ^ UInt64(layoutID.utf8.reduce(0) { $0 + Int($1) }))
        var failures: [String] = []
        for _ in 0..<2_000 {
            // Each word starts with a letter so its direction is known.
            var words: [String] = []
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                let useLatin = Bool.random(using: &rng)
                let head = (useLatin ? letters : targetLetters).randomElement(using: &rng)!
                let body = (0..<Int.random(in: 0...8, using: &rng)).map { _ in (useLatin ? latin : target).randomElement(using: &rng)! }
                words.append(head + body.joined())
            }
            let text = words.joined(separator: [" ", "\n", "  "].randomElement(using: &rng)!)
            let once = transformer.transformText(text)
            let twice = transformer.transformText(once)
            if twice != text { failures.append("\(text) → \(once) → \(twice)") }
            if once.filter(\.isWhitespace) != text.filter(\.isWhitespace) { failures.append("whitespace changed: \(text)") }
        }
        #expect(failures.isEmpty, "\(layoutID): \(failures.count) failures, first: \(failures.prefix(5))")
    }

    @Test func randomGarbageNeverCrashesAndKeepsLength() {
        let transformer = Layouts.transformer(Layouts.russianMac)
        let pool: [[String]] = [
            Array("abcxyzABC123!@#$%^&*()[]{};:'\",.<>/?`~\\|-_=+").map(String.init),
            Array("йцукенЁёЖжЭэХхЪъБбЮю№").map(String.init),
            ["👋", "👨‍👩‍👧", "é", "ñ", "中", "ك", "ש", "\u{301}", "\u{200D}"],
        ]
        var rng = SeededGenerator(state: 42)
        for _ in 0..<3_000 {
            let text = randomText(from: pool, using: &rng)
            let once = transformer.transformText(text)
            #expect(once.filter(\.isWhitespace) == text.filter(\.isWhitespace), "whitespace must survive: \(text)")
            _ = transformer.transformText(once)
        }
    }

    @Test func longTextStaysFast() {
        let transformer = Layouts.transformer(Layouts.russianMac)
        let text = String(repeating: "ghbdtn^ rfr ltkf& фыва ghjjk ", count: 4_000) // ~120k characters
        let started = Date()
        let once = transformer.transformText(text)
        #expect(transformer.transformText(once) == text)
        #expect(Date().timeIntervalSince(started) < 2, "two passes over 120k characters took too long")
    }

    // MARK: Unicode details

    @Test func decomposedCyrillicConverts() {
        let transformer = Layouts.transformer(Layouts.russianMac)
        let decomposed = "и\u{306}ог" // й as и + combining breve
        #expect(transformer.transformText(decomposed) == "qju")
    }

    @Test func untouchedTextKeepsItsExactUnicodeForm() {
        let transformer = Layouts.transformer(Layouts.russianMac)
        let decomposed = "か\u{3099} 123" // NFC would compose this into が
        #expect(transformer.transformText(decomposed) == decomposed)
        #expect(transformer.transformText(decomposed).unicodeScalars.count == decomposed.unicodeScalars.count)
    }

    @Test func arabicVowelMarksRoundTrip() throws {
        let transformer = Layouts.transformer("com.apple.keylayout.Arabic")
        let resolved = Layouts.resolved("com.apple.keylayout.Arabic")
        let fatha = try #require(resolved.forward["Q"])
        let letter = try #require(resolved.forward["f"])
        let typed = letter + fatha // letter with a vowel mark: one Character, two keys
        #expect(typed.count == 1)
        let latin = transformer.transformText(typed, typedInLayoutID: "com.apple.keylayout.Arabic")
        #expect(latin == "fQ")
        #expect(transformer.transformText(latin, typedInLayoutID: Layouts.abc) == typed)
    }

    @Test func germanDeadKeysAreMapped() throws {
        let resolved = Layouts.resolved(Layouts.german)
        #expect(resolved.forward["="] == "´", "the ´ key is dead on German; its accent must still be mapped")
        #expect(resolved.forward["§"] == "^", "^ is dead too")
        let transformer = Layouts.transformer(Layouts.german)
        #expect(transformer.transformText("a=b", typedInLayoutID: Layouts.abc) == "a´b")
        #expect(transformer.transformText("a´b", typedInLayoutID: Layouts.german) == "a=b")
    }
}

/// Smaller pieces around conversion: spelling, layout names, persistence of hotkeys and lists.
@MainActor
@Suite(.serialized)
struct SupportingBehaviourTests {
    init() {
        AppDefaults.resetForTesting()
    }

    @Test func spellingLanguageFollowsTheScript() {
        let available = ["en", "ru", "uk", "be"]
        #expect(SpellCheckManager.language(for: "привт", available: available) == "ru")
        #expect(SpellCheckManager.language(for: "привіт", available: available) == "uk")
        #expect(SpellCheckManager.language(for: "прывітанне", available: available) == "uk")
        #expect(SpellCheckManager.language(for: "ўсё", available: available) == "be")
        #expect(SpellCheckManager.language(for: "recieve", available: available) == "en")
        #expect(SpellCheckManager.language(for: "123", available: available) == nil)
        #expect(SpellCheckManager.language(for: "привт", available: ["en"]) == nil)
    }

    @Test func spellingFixesRussianAndEnglish() {
        let checker = SpellCheckManager()
        #expect(checker.fixText("привт как дила") == "привет как дела")
        #expect(checker.fixText("I recieve the wrold") == "I receive the world")
        #expect(checker.fixText("Привт") == "Привет", "capital kept")
        #expect(checker.fixText("all good here") == "all good here")
        #expect(checker.fixText("") == "")
    }

    @Test func shortLayoutNames() {
        #expect(KeyboardLayoutManager.extractShortNameFromLayoutID("com.apple.keylayout.Russian") == "RU", "russian contains 'us'")
        #expect(KeyboardLayoutManager.extractShortNameFromLayoutID("com.apple.keylayout.RussianWin") == "RU")
        #expect(KeyboardLayoutManager.extractShortNameFromLayoutID("com.apple.keylayout.US") == "EN")
        #expect(KeyboardLayoutManager.extractShortNameFromLayoutID("com.apple.keylayout.ABC") == "EN")
        #expect(KeyboardLayoutManager.extractShortNameFromLayoutID("com.apple.keylayout.Ukrainian-PC") == "UA")
        #expect(KeyboardLayoutManager.normalizeLanguageCode("ru") == "RU")
        #expect(KeyboardLayoutManager.normalizeLanguageCode("en-GB") == "GB")
        #expect(KeyboardLayoutManager.normalizeLanguageCode("pt-BR") == "PT")
    }

    @Test func hotKeysPersistAndLegacyKeyIsRead() throws {
        let manager = HotKeyManager()
        let newKey = HotKey(keyCode: 0, modifiers: [.maskControl, .maskAlternate])
        manager.updateLayoutHotKey(newKey)
        #expect(HotKeyManager().layoutHotKey == newKey)

        AppDefaults.resetForTesting()
        AppDefaults.store.set(try JSONEncoder().encode(HotKey(keyCode: 19, modifiers: [.maskCommand])), forKey: DefaultsKeys.savedHotKey)
        #expect(HotKeyManager().layoutHotKey == HotKey(keyCode: 19, modifiers: [.maskCommand]))
    }

    @Test func exclusionsPersistAndDeduplicate() {
        let manager = ExclusionManager()
        manager.addExcludedApp(ExcludedApp(name: "Finder", bundleID: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app"))
        manager.addExcludedApp(ExcludedApp(name: "Finder again", bundleID: "com.apple.finder", path: "/x"))
        #expect(manager.excludedApps.count == 1)
        #expect(ExclusionManager().isAppExcluded(bundleID: "com.apple.finder"))
        manager.removeExcludedApp(manager.excludedApps[0])
        #expect(!ExclusionManager().isAppExcluded(bundleID: "com.apple.finder"))
    }

    @Test func smartLayoutRules() {
        let layouts = KeyboardLayoutManager()
        let smart = SmartLayoutManager(keyboardLayoutManager: layouts)
        smart.setRule(bundleID: "com.apple.TextEdit", appName: "TextEdit", layoutID: Layouts.abc)
        smart.setRule(bundleID: "com.apple.TextEdit", appName: "TextEdit", layoutID: Layouts.russianMac)
        #expect(smart.defaultRules.count == 1, "one rule per app")
        #expect(smart.defaultRules.first?.layoutID == Layouts.russianMac)
        #expect(SmartLayoutManager(keyboardLayoutManager: layouts).defaultRules.count == 1, "rules persist")

        smart.removeRule(for: "com.apple.TextEdit")
        #expect(smart.defaultRules.isEmpty)
    }

    @Test func smartLayoutRemembersTheLayoutOnDeactivate() throws {
        let layouts = KeyboardLayoutManager()
        let smart = SmartLayoutManager(keyboardLayoutManager: layouts)
        smart.isEnabled = true
        defer { smart.isEnabled = false }
        let finder = try #require(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" })
        let current = try #require(layouts.currentLayoutID)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: finder]
        )
        let remembered = try #require(smart.publishedRememberedLayouts.first { $0.appBundleID == "com.apple.finder" })
        #expect(remembered.layoutID == current)

        smart.forget(bundleID: "com.apple.finder")
        #expect(!smart.publishedRememberedLayouts.contains { $0.appBundleID == "com.apple.finder" })
    }

    @Test func uninstalledRememberedAppsCanBeForgotten() {
        AppDefaults.store.set(["com.apple.TextEdit": Layouts.abc, "com.example.removed-app": Layouts.russianMac], forKey: DefaultsKeys.rememberedAppLayouts)
        let smart = SmartLayoutManager(keyboardLayoutManager: KeyboardLayoutManager())
        #expect(smart.publishedRememberedLayouts.first { $0.appBundleID == "com.example.removed-app" }?.isInstalled == false)
        #expect(smart.publishedRememberedLayouts.first { $0.appBundleID == "com.apple.TextEdit" }?.isInstalled == true)
        smart.forgetUninstalledApps()
        #expect(smart.publishedRememberedLayouts.map(\.appBundleID) == ["com.apple.TextEdit"])
    }

    @Test func appIconsAreSmallAndMissingAppsAreCached() {
        let icon = IconCache.shared.icon(for: "com.apple.TextEdit")
        #expect(icon.size == NSSize(width: 32, height: 32))
        #expect(icon.representations.count == 1, "only the small representation is kept")
        #expect(icon.representations.first.map { $0.pixelsWide <= 64 } == true)
        let missing = IconCache.shared.icon(for: "com.example.removed-app")
        #expect(missing === IconCache.shared.icon(for: "com.example.removed-app"), "missing apps cost one lookup")
    }

    @Test func smartLayoutIgnoresItself() {
        let layouts = KeyboardLayoutManager()
        let smart = SmartLayoutManager(keyboardLayoutManager: layouts)
        smart.isEnabled = true
        defer { smart.isEnabled = false }
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )
        #expect(!smart.publishedRememberedLayouts.contains { $0.appBundleID == Bundle.main.bundleIdentifier })
    }
}
