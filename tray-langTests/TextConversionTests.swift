import Testing
@testable import tray_lang

/// Behaviour of the converter on real-looking text, on the user's own pair (ABC + Russian Mac) and on Russian – PC.
struct TextConversionTests {
    let mac = Layouts.transformer(Layouts.russianMac)
    let pc = Layouts.transformer(Layouts.russianPC)

    // MARK: Mixed text — the reported bug

    @Test func mixedTextConvertsEachWordToTheOtherSide() {
        #expect(mac.transformText("фыва ghjjk") == "asdf проол")
        #expect(mac.transformText("asdf проол") == "фыва ghjjk")
        #expect(pc.transformText("фыва ghjjk") == "asdf проол")
    }

    @Test func mixedTextRoundTrips() {
        let samples = [
            "фыва ghjjk",
            "ghbdtn мир",
            "Привет, ghbdtn! Как дела?",
            "rfr ltkf, мир; ok",
            "git status и пше ыефегы",
            "ЗАГЛАВНЫЕ lowercase СмЕшАнНыЕ",
        ]
        for transformer in [mac, pc] {
            for sample in samples {
                let once = transformer.transformText(sample)
                #expect(once != sample, "\(sample) did not change")
                #expect(transformer.transformText(once) == sample, "\(sample) → \(once) → \(transformer.transformText(once))")
            }
        }
    }

    @Test func mixedLettersInsideOneWordFlipIndividually() {
        #expect(mac.transformText("ghbdtnмир") == "приветvbh")
        #expect(mac.transformText(mac.transformText("ghbdtnмир")) == "ghbdtnмир")
    }

    // MARK: Punctuation follows its word

    @Test func russianMacPunctuation() {
        // Shift+6 / Shift+7 type , and . on Russian (Mac).
        #expect(mac.transformText("ghbdtn^ rfr ltkf&") == "привет, как дела.")
        #expect(mac.transformText("привет, как дела.") == "ghbdtn^ rfr ltkf&")
        // ё sits on the \\ key on Russian (Mac).
        #expect(mac.transformText("\\krf") == "ёлка")
    }

    @Test func russianPCPunctuation() {
        #expect(pc.transformText("ghbdtn? rfr ltkf/") == "привет, как дела.")
        #expect(pc.transformText("привет, как дела.") == "ghbdtn? rfr ltkf/")
        #expect(pc.transformText("ghbdtn? rfr ltkf/") != mac.transformText("ghbdtn? rfr ltkf/"))
    }

    @Test func commaAndPeriodKeysBecomeLettersInLatinWords() {
        // , and . are the б and ю keys.
        #expect(mac.transformText("k.,k.") == "люблю")
        #expect(mac.transformText("люблю") == "k.,k.")
    }

    @Test func urlsRoundTrip() {
        for transformer in [mac, pc] {
            for url in ["https://github.com/s00d/tray-lang/releases/tag/v1.48", "https://example.com/a?b=1&c=2#top", "user@example.com"] {
                let once = transformer.transformText(url)
                #expect(once != url)
                #expect(transformer.transformText(once) == url, "\(url) → \(once)")
            }
        }
        #expect(pc.transformText("реезыЖ..пшергиюсщь") == "https://github.com")
    }

    @Test func gitCommandTypedInRussian() {
        #expect(mac.transformText("пше сруслщге") == "git checkout")
        #expect(pc.transformText("пше сруслщге") == "git checkout")
    }

    // MARK: Whitespace and untouched characters

    @Test func whitespaceIsPreservedExactly() {
        #expect(mac.transformText("  ghbdtn\n\tvbh  ") == "  привет\n\tмир  ")
        #expect(mac.transformText("") == "")
        #expect(mac.transformText(" \n ") == " \n ")
        #expect(mac.transformText("ghbdtn\r\nvbh") == "привет\r\nмир")
    }

    @Test func charactersOutsideBothLayoutsStayAsTheyAre() {
        #expect(mac.transformText("ghbdtn 👋 €") == "привет 👋 €")
        #expect(mac.transformText("2024 1234") == "2024 1234")
    }

    // MARK: Words without layout-specific characters

    @Test func lonePunctuationUsesTheLayoutItWasTypedIn() {
        // "?" typed on ABC means the user wanted what that key types on Russian (Mac): also "?" — unchanged.
        #expect(mac.transformText("&", typedInLayoutID: Layouts.abc) == ".")
        #expect(mac.transformText(".", typedInLayoutID: Layouts.russianMac) == "&")
        #expect(mac.transformText(".", typedInLayoutID: Layouts.abc) == "ю")
        #expect(pc.transformText(",", typedInLayoutID: Layouts.russianPC) == "?")
        #expect(pc.transformText("?", typedInLayoutID: Layouts.abc) == ",")
    }

    @Test func punctuationOnlyWordsBorrowTheNeighbourDirection() {
        #expect(mac.transformText("ghbdtn ^ vbh") == "привет , мир")
        #expect(mac.transformText("привет , мир") == "ghbdtn ^ vbh")
        #expect(mac.transformText("... ghbdtn") == "ююю привет")
    }

    // MARK: Direction reported for the layout switch

    @Test func reportsWhereTheTextEnds() {
        #expect(mac.convert("ghbdtn").endsOn == .toTarget)
        #expect(mac.convert("руддщ").endsOn == .toSource)
        #expect(mac.convert("руддщ ghbdtn").endsOn == .toTarget, "last converted word decides")
        #expect(mac.convert("123 👋").endsOn == nil)
        #expect(mac.convert("").endsOn == nil)
    }

    @Test func layoutToSelectAfterConversion() {
        let enabled = [Layouts.abc, Layouts.russianMac]
        let resolved = Layouts.resolved(Layouts.russianMac)
        #expect(TextTransformer.layoutIDToSelect(after: .toTarget, resolved: resolved, enabled: enabled) == Layouts.russianMac)
        #expect(TextTransformer.layoutIDToSelect(after: .toSource, resolved: resolved, enabled: enabled) == Layouts.abc)
        // User types on US, not ABC: still go back to their latin layout.
        #expect(TextTransformer.layoutIDToSelect(after: .toSource, resolved: resolved, enabled: ["com.apple.keylayout.US", Layouts.russianMac]) == "com.apple.keylayout.US")
        // Profile is Russian – PC but only Russian (Mac) is enabled: pick the layout that types the letters.
        #expect(TextTransformer.layoutIDToSelect(after: .toTarget, resolved: Layouts.resolved(Layouts.russianPC), enabled: enabled) == Layouts.russianMac)
        #expect(TextTransformer.layoutIDToSelect(after: .toTarget, resolved: resolved, enabled: [Layouts.abc]) == nil)
    }

    // MARK: Auto profile

    @Test func autoFollowsEnabledLayouts() {
        var enabled = [Layouts.abc, Layouts.russianMac]
        let auto = TextTransformer(profile: .auto, enabledLayouts: { enabled })
        #expect(auto.transformText("ghbdtn^") == "привет,")

        enabled = [Layouts.abc, Layouts.russianPC]
        #expect(auto.transformText("ghbdtn?") == "привет,")

        enabled = [Layouts.abc, "com.apple.keylayout.Greek"]
        #expect(auto.transformText("kalhmera") == "καλημερα")

        enabled = [Layouts.abc]
        #expect(auto.transformText("ghbdtn") == "ghbdtn", "nothing to convert to")
    }

    @Test func autoUsesTheUsersLatinLayoutAsSource() {
        let auto = TextTransformer(profile: .auto, enabledLayouts: { ["com.apple.keylayout.Dvorak", Layouts.russianMac] })
        // On Dvorak the Y key types "f"; on Russian the same key types "н".
        #expect(auto.transformText("f") == "н")
    }

    // MARK: Other built-ins

    @Test(arguments: [
        ("com.apple.keylayout.Ukrainian-PC", "ghbdsn", "привіт"),
        ("com.apple.keylayout.Greek", "kalhmera", "καλημερα"),
        ("com.apple.keylayout.German", "Zeit", "Yeit"),
        ("com.apple.keylayout.Dvorak", "jdpps", "hello"),
    ])
    func otherLayouts(layoutID: String, typed: String, expected: String) {
        let transformer = Layouts.transformer(layoutID)
        #expect(transformer.transformText(typed, typedInLayoutID: Layouts.abc) == expected)
        #expect(transformer.transformText(expected, typedInLayoutID: layoutID) == typed)
    }
}
