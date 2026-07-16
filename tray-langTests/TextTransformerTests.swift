import Testing
@testable import tray_lang

struct TextTransformerTests {
    /// Все печатные символы ANSI US (без Shift и со Shift), как на физической клавиатуре.
    private static let usKeyboardSymbols: [String] = [
        "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=",
        "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\",
        "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'",
        "z", "x", "c", "v", "b", "n", "m", ",", ".", "/",
        "~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+",
        "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "{", "}", "|",
        "A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "\"",
        "Z", "X", "C", "V", "B", "N", "M", "<", ">", "?",
    ]

    private static let fullLayoutProfileNames: [String] = [
        "Russian (QWERTY ↔ ЙЦУКЕН)",
        "Ukrainian (QWERTY ↔ ЙЦУКЕН)",
        "Belarusian (QWERTY ↔ Беларуская)",
    ]

    /// Символы, которые после туда-обратно могут смениться из‑за общей цели в профиле.
    private static let knownRoundTripAliases: [String: [String: String]] = [
        // @ и } оба → "; обратный маппинг предпочитает @
        "Belarusian (QWERTY ↔ Беларуская)": ["}": "@"],
    ]

    private func transformer(forProfileNamed name: String) -> TextTransformer {
        let profiles = ConversionProfile.defaultProfiles()
        guard let profile = profiles.first(where: { $0.name == name }) else {
            fatalError("Profile missing: \(name)")
        }
        return TextTransformer(profiles: profiles, activeProfileID: profile.id)
    }

    private func russianTransformer() -> TextTransformer {
        transformer(forProfileNamed: "Russian (QWERTY ↔ ЙЦУКЕН)")
    }

    private func defaultProfile(named name: String) -> ConversionProfile {
        guard let profile = ConversionProfile.defaultProfiles().first(where: { $0.name == name }) else {
            fatalError("Default profile missing: \(name)")
        }
        return profile
    }

    private func expectedAfterRoundTrip(_ input: String, profileName: String) -> String {
        guard let aliases = Self.knownRoundTripAliases[profileName] else { return input }
        return input.map { char in
            let key = String(char)
            return aliases[key] ?? key
        }.joined()
    }

    // MARK: - Полная клавиатура через TextTransformer

    @Test(arguments: fullLayoutProfileNames)
    func fullKeyboardRoundTripsViaTransformer(profileName: String) {
        let transformer = transformer(forProfileNamed: profileName)
        let keyboard = Self.usKeyboardSymbols.joined()

        let converted = transformer.transformText(keyboard)
        #expect(converted != keyboard, "«\(profileName)»: конвертация не изменила строку")

        let restored = transformer.transformText(converted)
        let expected = expectedAfterRoundTrip(keyboard, profileName: profileName)
        #expect(
            restored == expected,
            "«\(profileName)»: туда-обратно не восстановило клавиатуру.\nожидали: \(expected)\nполучили: \(restored)"
        )
    }

    @Test(arguments: fullLayoutProfileNames)
    func eachKeyboardSymbolRoundTripsViaTransformer(profileName: String) {
        let transformer = transformer(forProfileNamed: profileName)
        let aliases = Self.knownRoundTripAliases[profileName] ?? [:]
        var failures: [String] = []

        for symbol in Self.usKeyboardSymbols {
            // Оборачиваем в латинские буквы: иначе у одиночной пунктуации
            // TextTransformer выбирает направление по буквам (0==0 → toLatin).
            let sample = "qz\(symbol)wz"
            let once = transformer.transformText(sample)
            let twice = transformer.transformText(once)

            let expectedSymbol = aliases[symbol] ?? symbol
            let expected = "qz\(expectedSymbol)wz"

            if twice != expected {
                failures.append("\(symbol) → … → \(twice) (ожидали \(expected))")
            }
        }

        #expect(
            failures.isEmpty,
            "«\(profileName)» сломанные символы:\n\(failures.joined(separator: "\n"))"
        )
    }

    @Test(arguments: fullLayoutProfileNames)
    func eachKeyboardRowRoundTripsViaTransformer(profileName: String) {
        let transformer = transformer(forProfileNamed: profileName)
        let rows: [[String]] = [
            Array(Self.usKeyboardSymbols[0..<13]),   // `123...=
            Array(Self.usKeyboardSymbols[13..<26]),  // qwerty...\
            Array(Self.usKeyboardSymbols[26..<37]),  // asdf...'
            Array(Self.usKeyboardSymbols[37..<47]),  // zxcv.../
            Array(Self.usKeyboardSymbols[47..<60]),  // ~!@...+
            Array(Self.usKeyboardSymbols[60..<73]),  // QWERTY...|
            Array(Self.usKeyboardSymbols[73..<84]),  // ASDF..."
            Array(Self.usKeyboardSymbols[84..<94]),  // ZXCV...?
        ]

        for (index, row) in rows.enumerated() {
            let text = "ab" + row.joined() + "cd"
            let restored = transformer.transformText(transformer.transformText(text))
            let expected = expectedAfterRoundTrip(text, profileName: profileName)
            #expect(
                restored == expected,
                "«\(profileName)» ряд #\(index) не восстановился.\nожидали: \(expected)\nполучили: \(restored)"
            )
        }
    }

    @Test(arguments: fullLayoutProfileNames)
    func convertedKeyboardIsMostlyNonLatinThenRestores(profileName: String) {
        let transformer = transformer(forProfileNamed: profileName)
        let keyboard = Self.usKeyboardSymbols.joined()
        let converted = transformer.transformText(keyboard)

        let latinLetters = converted.filter { $0.isLetter && $0.isASCII }
        let nonASCII = converted.filter { !$0.isASCII }
        #expect(
            nonASCII.count > latinLetters.count,
            "«\(profileName)»: после конвертации ожидаем доминирование не-ASCII (\(nonASCII.count) vs latin \(latinLetters.count))"
        )

        let restored = transformer.transformText(converted)
        #expect(restored == expectedAfterRoundTrip(keyboard, profileName: profileName))
    }

    @Test(arguments: fullLayoutProfileNames)
    func shiftAndUnshiftRowsRoundTripTogether(profileName: String) {
        let transformer = transformer(forProfileNamed: profileName)
        // Нижний + верхний регистр одной «физической» зоны
        let mixed = "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./"
            + "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"

        let restored = transformer.transformText(transformer.transformText(mixed))
        #expect(restored == expectedAfterRoundTrip(mixed, profileName: profileName))
    }

    // MARK: - URL / практические кейсы (русский)

    @Test func decodesMistypedGitHubIssuesURL() {
        let transformer = russianTransformer()
        let mistyped = "реезыЖ..пшергиюсщь.шыыгуы.кусу"
        let expected = "https://github.com/issues/rece"

        #expect(transformer.transformText(mistyped) == expected)
    }

    @Test func roundTripsGitHubIssuesURL() {
        let transformer = russianTransformer()
        let url = "https://github.com/issues/recent"
        let mistyped = transformer.transformText(url)

        #expect(transformer.transformText(mistyped) == url)
    }

    @Test func decodesMistypedReleaseTagURL() {
        let transformer = russianTransformer()
        let mistyped = "реезыЖ..пшергиюсщь.ы00в.екфн-дфтп.кудуфыуы.ефп.м1ю43"
        let expected = "https://github.com/s00d/tray-lang/releases/tag/v1.43"

        #expect(transformer.transformText(mistyped) == expected)
    }

    @Test func roundTripsReleaseTagURL() {
        let transformer = russianTransformer()
        let url = "https://github.com/s00d/tray-lang/releases/tag/v1.43"
        let mistyped = transformer.transformText(url)

        #expect(mistyped == "реезыЖ..пшергиюсщь.ы00в.екфн-дфтп.кудуфыуы.ефп.м1ю43")
        #expect(transformer.transformText(mistyped) == url)
    }

    @Test func roundTripsReleaseTagURL_v1_48() {
        let transformer = russianTransformer()
        let url = "https://github.com/s00d/tray-lang/releases/tag/v1.48"

        let once = transformer.transformText(url)
        #expect(once != url)

        let twice = transformer.transformText(once)
        #expect(twice == url)
    }

    @Test func refreshesBuiltInProfilesFromCodeWhenStoredProfilesAreStale() {
        var staleRussian = defaultProfile(named: "Russian (QWERTY ↔ ЙЦУКЕН)")
        staleRussian.mapping["0"] = ")"

        let custom = ConversionProfile(
            name: "My Custom Profile",
            isEditable: true,
            mapping: ["a": "ф"]
        )

        let merged = TextTransformer.mergeStoredProfilesWithDefaults([staleRussian, custom])

        let russian = try! #require(merged.first(where: { $0.name == "Russian (QWERTY ↔ ЙЦУКЕН)" }))
        #expect(russian.mapping["0"] == "0")
        #expect(russian.mapping["0"] != staleRussian.mapping["0"])
        #expect(russian.id == staleRussian.id)
        #expect(merged.contains(where: { $0.name == custom.name && $0.isEditable }))
    }

    @Test func doesNotTurnSlashesIntoYuOnSecondPass() {
        let transformer = russianTransformer()
        let url = "https://github.com/s00d/tray-lang"
        let once = transformer.transformText(url)
        let twice = transformer.transformText(once)

        #expect(twice == url)
        #expect(!twice.contains("ю"))
    }

    @Test func preservesDollarAndHashThroughLatinRoundTrip() {
        let transformer = russianTransformer()
        let url = "https://example.com/v1.$#"
        let mistyped = transformer.transformText(url)
        let restored = transformer.transformText(mistyped)
        #expect(restored == url)
        #expect(restored.contains("$"))
        #expect(restored.contains("#"))
    }

    @Test func emptyAndWhitespacePassThrough() {
        let transformer = russianTransformer()
        #expect(transformer.transformText("") == "")
        #expect(transformer.transformText("   ") == "   ")
    }

    @Test func punctuationHeavyLatinRoundTripsWithoutSlashCorruption() {
        let transformer = russianTransformer()
        let input = "https://a.com/b"
        let once = transformer.transformText(input)
        #expect(once != input)
        #expect(transformer.transformText(once) == input)
    }

    @Test func mistypedGitCheckoutDecodesToLatin() {
        let transformer = russianTransformer()
        let mistyped = "пше сруслщге"
        #expect(transformer.transformText(mistyped) == "git checkout")
    }

    @Test func russianPipeAndSlashRoundTripInPath() {
        let transformer = russianTransformer()
        // | → / на RussianWin; / → . ; путь с обоими
        let input = "C:\\foo|bar/baz"
        let restored = transformer.transformText(transformer.transformText(input))
        #expect(restored == input)
    }

    @Test func russianAllLettersAlphabetRoundTrip() {
        let transformer = russianTransformer()
        let lower = "qwertyuiopasdfghjklzxcvbnm"
        let upper = "QWERTYUIOPASDFGHJKLZXCVBNM"
        #expect(transformer.transformText(transformer.transformText(lower)) == lower)
        #expect(transformer.transformText(transformer.transformText(upper)) == upper)
    }
}
