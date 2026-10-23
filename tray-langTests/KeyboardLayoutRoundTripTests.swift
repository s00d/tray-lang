import Testing
@testable import tray_lang

/// Tables come from the macOS layouts themselves, so these tests pin the facts the user relies on.
struct SystemKeyboardLayoutTests {
    @Test(arguments: [Layouts.abc] + Layouts.common)
    func everyBuiltInLayoutHasAKeyTable(layoutID: String) throws {
        let table = try #require(SystemKeyboardLayouts.keyTable(layoutID: layoutID), "\(layoutID) is missing on this Mac")
        #expect(table.count == SystemKeyboardLayouts.printableKeyCodes.count)
        #expect(table.values.filter { !$0.plain.isEmpty }.count >= 40, "\(layoutID) types almost nothing")
    }

    @Test func abcIsPlainQwerty() throws {
        let row = Layouts.characters(Layouts.abc).prefix(26).joined()
        #expect(row == "`~1!2@3#4$5%6^7&8*9(0)-_=+")
        #expect(SystemKeyboardLayouts.keyTable(layoutID: Layouts.abc)?[12]?.plain == "q")
    }

    /// The two Russian layouts differ on punctuation; the old hand-written profile mixed them up.
    @Test func russianMacAndPCDifferWhereMacOSSaysTheyDo() {
        let mac = Layouts.resolved(Layouts.russianMac).forward
        let pc = Layouts.resolved(Layouts.russianPC).forward

        #expect(mac["^"] == ",")
        #expect(mac["&"] == ".")
        #expect(mac["*"] == ";")
        #expect(mac["$"] == "%")
        #expect(mac["%"] == ":")
        #expect(mac["\\"] == "ё")
        #expect(mac["`"] == "]")
        #expect(mac["/"] == nil, "/ types / on Russian (Mac): identical keys are not mapped")

        #expect(pc["^"] == ":")
        #expect(pc["&"] == "?")
        #expect(pc["/"] == ".")
        #expect(pc["?"] == ",")
        #expect(pc["$"] == ";")
        #expect(pc["\\"] == "\\" || pc["\\"] == nil)
        #expect(pc["|"] == "/")

        for (key, letter) in [("q", "й"), ("f", "а"), ("[", "х"), ("]", "ъ"), (";", "ж"), ("'", "э"), (",", "б"), (".", "ю")] {
            #expect(mac[key] == letter, "Mac \(key)")
            #expect(pc[key] == letter, "PC \(key)")
        }
    }

    @Test func latinDetection() {
        #expect(SystemKeyboardLayouts.isLatin(layoutID: Layouts.abc))
        #expect(SystemKeyboardLayouts.isLatin(layoutID: "com.apple.keylayout.US"))
        #expect(SystemKeyboardLayouts.isLatin(layoutID: Layouts.german))
        #expect(SystemKeyboardLayouts.isLatin(layoutID: "com.apple.keylayout.Dvorak"))
        #expect(!SystemKeyboardLayouts.isLatin(layoutID: Layouts.russianMac))
        #expect(!SystemKeyboardLayouts.isLatin(layoutID: "com.apple.keylayout.Greek"))
        #expect(!SystemKeyboardLayouts.isLatin(layoutID: "com.example.missing"))
    }

    @Test func autoPairUsesEnabledLatinAndFirstOtherLayout() throws {
        let pair = try #require(SystemKeyboardLayouts.enabledAutoPair(enabled: ["com.apple.keylayout.US", Layouts.russianMac, Layouts.ukrainianPC]))
        #expect(pair.source == "com.apple.keylayout.US")
        #expect(pair.target == Layouts.russianMac)

        let noLatin = try #require(SystemKeyboardLayouts.enabledAutoPair(enabled: [Layouts.russianPC]))
        #expect(noLatin.source == Layouts.abc)
        #expect(noLatin.target == Layouts.russianPC)

        #expect(SystemKeyboardLayouts.enabledAutoPair(enabled: [Layouts.abc]) == nil)
        #expect(SystemKeyboardLayouts.enabledAutoPair(enabled: []) == nil)
    }

    @Test func layoutTypingCharacterIsFoundAmongEnabled() {
        let enabled = [Layouts.abc, Layouts.russianMac]
        #expect(SystemKeyboardLayouts.enabledLayoutID(typing: "а", atKeyCode: 3, enabled: enabled) == Layouts.russianMac)
        #expect(SystemKeyboardLayouts.enabledLayoutID(typing: "f", atKeyCode: 3, enabled: enabled) == Layouts.abc)
        #expect(SystemKeyboardLayouts.enabledLayoutID(typing: "α", atKeyCode: 3, enabled: enabled) == nil)
    }

    @Test func builtInListHasBothRussianLayoutsAndAuto() {
        let names = SystemKeyboardLayouts.commonLayoutIDs
        #expect(names.contains(Layouts.russianMac))
        #expect(names.contains(Layouts.russianPC))
        let profiles = TextTransformer(profile: .auto, enabledLayouts: { [Layouts.abc, Layouts.russianMac] }).builtInProfiles()
        #expect(profiles.first?.isAuto == true)
        #expect(profiles.filter { $0.targetLayoutID == Layouts.russianMac }.count == 1, "enabled layout listed once")
        #expect(profiles.contains { $0.targetLayoutID == Layouts.russianPC })
        #expect(!profiles.contains { $0.targetLayoutID == Layouts.abc })
    }

    @Test func allInstalledLayoutsAreSortedAndSkipLatinSources() {
        let all = SystemKeyboardLayouts.allInstalledLayouts()
        #expect(all.count > 50)
        #expect(!all.contains { $0.id == Layouts.abc })
        #expect(all.map(\.name) == all.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}

/// "Convert twice → back where you started", for every key of both layouts of every built-in profile.
struct KeyboardLayoutRoundTripTests {
    /// Two keys that type the same character can't both come back. Allowed: the ISO key (§/± on ABC,
    /// keycode 10), and the duplicates macOS itself ships in these layouts.
    static let layoutDuplicates: [String: Set<String>] = [
        "com.apple.keylayout.Arabic": ["`"],           // ` and _ both type ـ (tatweel)
        "com.apple.keylayout.Byelorussian": ["}"],     // ] and } both type '
        "com.apple.keylayout.Hebrew": ["K"],           // ⇧K and ⇧C both type לֹ
    ]

    @Test(arguments: Layouts.common)
    func onlyKnownDuplicateKeysAlias(layoutID: String) throws {
        let resolved = Layouts.resolved(layoutID)
        let table = try #require(SystemKeyboardLayouts.keyTable(layoutID: Layouts.abc))
        let allowed = Set([table[10]?.plain, table[10]?.shifted].compactMap { $0 }).union(Self.layoutDuplicates[layoutID] ?? [])
        let aliased = resolved.forward.keys.filter { Layouts.roundTripAlias($0, resolved) != $0 }
        let unexpected = aliased.filter { !allowed.contains($0) }.sorted()
        #expect(unexpected.isEmpty, "\(layoutID): keys that don't come back: \(unexpected)")
    }

    @Test(arguments: Layouts.common)
    func everyLatinKeyRoundTripsAlone(layoutID: String) {
        let transformer = Layouts.transformer(layoutID)
        let resolved = Layouts.resolved(layoutID)
        var failures: [String] = []
        for char in Layouts.characters(Layouts.abc) {
            let once = transformer.transformText(char, typedInLayoutID: Layouts.abc)
            let twice = transformer.transformText(once, typedInLayoutID: layoutID)
            let expected = Layouts.roundTripAlias(char, resolved)
            if twice != expected { failures.append("\(char) → \(once) → \(twice)") }
        }
        #expect(failures.isEmpty, "\(layoutID):\n\(failures.joined(separator: "\n"))")
    }

    @Test(arguments: Layouts.common)
    func everyTargetKeyRoundTripsAlone(layoutID: String) {
        let transformer = Layouts.transformer(layoutID)
        let resolved = Layouts.resolved(layoutID)
        var failures: [String] = []
        for char in Layouts.characters(layoutID) {
            let once = transformer.transformText(char, typedInLayoutID: layoutID)
            let twice = transformer.transformText(once, typedInLayoutID: Layouts.abc)
            let expected = resolved.inverse[char].map { Layouts.roundTripAlias($0, resolved) }.flatMap { resolved.forward[$0] } ?? char
            if twice != expected { failures.append("\(char) → \(once) → \(twice)") }
        }
        #expect(failures.isEmpty, "\(layoutID):\n\(failures.joined(separator: "\n"))")
    }

    /// The whole keyboard as one space-separated line, both directions, without any layout hint.
    @Test(arguments: Layouts.common)
    func wholeKeyboardRoundTripsBothWays(layoutID: String) {
        let transformer = Layouts.transformer(layoutID)
        let resolved = Layouts.resolved(layoutID)

        let latin = Layouts.characters(Layouts.abc)
        let latinLine = latin.joined(separator: " ")
        let latinBack = transformer.transformText(transformer.transformText(latinLine, typedInLayoutID: Layouts.abc), typedInLayoutID: layoutID)
        #expect(latinBack == latin.map { Layouts.roundTripAlias($0, resolved) }.joined(separator: " "))

        let target = Layouts.characters(layoutID)
        let targetLine = target.joined(separator: " ")
        let targetOnce = transformer.transformText(targetLine, typedInLayoutID: layoutID)
        let targetBack = transformer.transformText(targetOnce, typedInLayoutID: Layouts.abc)
        let expectedTarget = target.map { char in
            resolved.inverse[char].map { Layouts.roundTripAlias($0, resolved) }.flatMap { resolved.forward[$0] } ?? char
        }
        #expect(targetBack == expectedTarget.joined(separator: " "))
    }

    /// Russian keyboard, every key, inside Russian words — what a real sentence looks like.
    @Test(arguments: [Layouts.russianMac, Layouts.russianPC])
    func everyRussianKeyRoundTripsInsideRussianWords(layoutID: String) {
        let transformer = Layouts.transformer(layoutID)
        var failures: [String] = []
        for char in Layouts.characters(layoutID) {
            let sample = "фы\(char)ва"
            let twice = transformer.transformText(transformer.transformText(sample))
            if twice != sample { failures.append("\(sample) → \(transformer.transformText(sample)) → \(twice)") }
        }
        #expect(failures.isEmpty, "\(layoutID):\n\(failures.joined(separator: "\n"))")
    }

    @Test(arguments: [Layouts.russianMac, Layouts.russianPC])
    func everyLatinKeyRoundTripsInsideLatinWords(layoutID: String) {
        let transformer = Layouts.transformer(layoutID)
        let resolved = Layouts.resolved(layoutID)
        var failures: [String] = []
        for char in Layouts.characters(Layouts.abc) {
            let sample = "as\(char)df"
            let expected = "as\(Layouts.roundTripAlias(char, resolved))df"
            let twice = transformer.transformText(transformer.transformText(sample))
            if twice != expected { failures.append("\(sample) → \(transformer.transformText(sample)) → \(twice)") }
        }
        #expect(failures.isEmpty, "\(layoutID):\n\(failures.joined(separator: "\n"))")
    }
}
