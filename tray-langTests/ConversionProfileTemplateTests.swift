import Testing
@testable import tray_lang

// Тесты шаблонов раскладок — без TextTransformer, только пары из languageTemplates.

private enum TemplateTestHelpers {
    static func forwardMapping(from pairs: [(String, String)]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: pairs)
    }

    static func inverseMapping(from pairs: [(String, String)]) -> [String: String] {
        KeyboardMapping.createInverseMapping(from: forwardMapping(from: pairs))
    }

    static func applyMapping(_ text: String, mapping: [String: String]) -> String {
        text.reduce(into: "") { result, char in
            let key = String(char)
            result += mapping[key] ?? key
        }
    }
}

struct ConversionProfileTemplateTests {
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

    private static let fullLayoutTemplateNames: [String] = [
        "Russian (QWERTY ↔ ЙЦУКЕН)",
        "Ukrainian (QWERTY ↔ ЙЦУКЕН)",
        "Belarusian (QWERTY ↔ Беларуская)",
    ]

    /// Цели, на которые на реальной раскладке претендуют несколько QWERTY-клавиш.
    /// Обратный маппинг сохраняет первый source (для белорусского: `"` ← `@`, не `}`).
    private static let sharedForwardTargets: [String: Set<String>] = [
        "Belarusian (QWERTY ↔ Беларуская)": ["\""],
    ]

    private static let partialTemplateNames: [String] = {
        let full = Set(fullLayoutTemplateNames)
        return languageTemplates.keys.filter { !full.contains($0) }.sorted()
    }()

    private static let templateNames: [String] = languageTemplates.keys.sorted()

    private static func isSharedTarget(_ target: String, templateName: String) -> Bool {
        sharedForwardTargets[templateName]?.contains(target) == true
    }

    // MARK: - По каждому шаблону

    @Test(arguments: templateNames)
    func forwardMappingContainsEveryTemplatePair(templateName: String) throws {
        let pairs = try #require(languageTemplates[templateName])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)

        for (source, target) in pairs {
            #expect(forward[source] == target, "В «\(templateName)» нет пары \(source) → \(target)")
        }
    }

    @Test(arguments: fullLayoutTemplateNames)
    func eachSymbolRoundTripsThroughForwardAndInverse(templateName: String) throws {
        let pairs = try #require(languageTemplates[templateName])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)
        let inverse = TemplateTestHelpers.inverseMapping(from: pairs)

        for (source, target) in pairs {
            #expect(forward[source] == target, "Прямой: \(source) в «\(templateName)»")

            if Self.isSharedTarget(target, templateName: templateName), inverse[target] != source {
                // Проигрышная клавиша в коллизии (например } при общем ")
                continue
            }

            let roundTripped = TemplateTestHelpers.applyMapping(target, mapping: inverse)
            #expect(
                roundTripped == source,
                "Обратный: \(target) → \(roundTripped), ожидался \(source) в «\(templateName)»"
            )

            let forwardRoundTripped = TemplateTestHelpers.applyMapping(
                TemplateTestHelpers.applyMapping(source, mapping: forward),
                mapping: inverse
            )
            #expect(
                forwardRoundTripped == source,
                "Туда-обратно: \(source) → … → \(forwardRoundTripped) в «\(templateName)»"
            )
        }
    }

    @Test(arguments: templateNames)
    func noDuplicateSourceKeysInTemplate(templateName: String) throws {
        let pairs = try #require(languageTemplates[templateName])
        var seen: Set<String> = []

        for (source, _) in pairs {
            #expect(!seen.contains(source), "Дублирующийся источник «\(source)» в «\(templateName)»")
            seen.insert(source)
        }
    }

    @Test(arguments: fullLayoutTemplateNames)
    func reportsInverseCollisions(templateName: String) throws {
        let pairs = try #require(languageTemplates[templateName])
        let inverse = TemplateTestHelpers.inverseMapping(from: pairs)
        var collisions: [String] = []

        for (source, target) in pairs {
            if inverse[target] != source {
                if Self.isSharedTarget(target, templateName: templateName) {
                    continue
                }
                collisions.append("\(target) → \(inverse[target] ?? "∅") (ожидался \(source))")
            }
        }

        #expect(collisions.isEmpty, "Коллизии обратного маппинга в «\(templateName)»: \(collisions.joined(separator: ", "))")
    }

    // MARK: - Полная раскладка QWERTY

    @Test(arguments: fullLayoutTemplateNames)
    func fullLayoutCoversAllUSKeyboardSymbols(templateName: String) throws {
        let pairs = try #require(languageTemplates[templateName])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)
        var missing: [String] = []

        for symbol in Self.usKeyboardSymbols where forward[symbol] == nil {
            missing.append(symbol)
        }

        #expect(missing.isEmpty, "В «\(templateName)» нет символов: \(missing.joined(separator: " "))")
    }

    @Test(arguments: fullLayoutTemplateNames)
    func fullKeyboardStringRoundTrips(templateName: String) throws {
        let pairs = try #require(languageTemplates[templateName])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)
        let inverse = TemplateTestHelpers.inverseMapping(from: pairs)

        let keyboard = Self.usKeyboardSymbols.joined()
        let converted = TemplateTestHelpers.applyMapping(keyboard, mapping: forward)
        let restored = TemplateTestHelpers.applyMapping(converted, mapping: inverse)

        if Self.sharedForwardTargets[templateName] == nil {
            #expect(restored == keyboard, "Полная строка клавиатуры не вернулась в «\(templateName)»")
        } else {
            // Все символы кроме проигравших в shared targets должны совпасть.
            for symbol in Self.usKeyboardSymbols {
                guard let target = forward[symbol] else { continue }
                if Self.isSharedTarget(target, templateName: templateName), inverse[target] != symbol {
                    continue
                }
                let roundTripped = TemplateTestHelpers.applyMapping(
                    TemplateTestHelpers.applyMapping(symbol, mapping: forward),
                    mapping: inverse
                )
                #expect(roundTripped == symbol, "Символ \(symbol) не вернулся в «\(templateName)»")
            }
        }
    }

    @Test(arguments: partialTemplateNames)
    func partialTemplatePairsAreForwardCorrect(templateName: String) throws {
        let pairs = try #require(languageTemplates[templateName])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)

        for (source, target) in pairs {
            #expect(forward[source] == target, "Прямой: \(source) → \(target) в «\(templateName)»")
        }
    }

    // MARK: - URL (набран в неверной раскладке)

    @Test func russianTemplateDecodesMistypedGitHubURL() throws {
        let templateName = "Russian (QWERTY ↔ ЙЦУКЕН)"
        let pairs = try #require(languageTemplates[templateName])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)
        let inverse = TemplateTestHelpers.inverseMapping(from: pairs)

        let url = "https://github.com/s00d/tray-lang"
        let mistyped = TemplateTestHelpers.applyMapping(url, mapping: forward)
        let decoded = TemplateTestHelpers.applyMapping(mistyped, mapping: inverse)

        #expect(mistyped == "реезыЖ..пшергиюсщь.ы00в.екфн-дфтп")
        #expect(decoded == url)
    }

    @Test func russianTemplateSlashAndDotAreDistinctKeys() throws {
        let pairs = try #require(languageTemplates["Russian (QWERTY ↔ ЙЦУКЕН)"])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)
        let inverse = TemplateTestHelpers.inverseMapping(from: pairs)

        // / и . — разные физические клавиши на ЙЦУКЕН
        #expect(forward["/"] == ".")
        #expect(forward["."] == "ю")
        #expect(inverse["."] == "/")
        #expect(inverse["ю"] == ".")
    }

    @Test func russianTemplateBackslashAndPipeMatchRussianWin() throws {
        let pairs = try #require(languageTemplates["Russian (QWERTY ↔ ЙЦУКЕН)"])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)
        let inverse = TemplateTestHelpers.inverseMapping(from: pairs)

        #expect(forward["\\"] == "\\")
        #expect(forward["|"] == "/")
        #expect(inverse["\\"] == "\\")
        #expect(inverse["/"] == "|")
    }

    @Test func ukrainianTemplateMatchesUkrainianPCBracketsAndSlash() throws {
        let pairs = try #require(languageTemplates["Ukrainian (QWERTY ↔ ЙЦУКЕН)"])
        let forward = TemplateTestHelpers.forwardMapping(from: pairs)

        #expect(forward["["] == "х")
        #expect(forward["]"] == "ї")
        #expect(forward["\\"] == "ʼ")
        #expect(forward["|"] == "₴")
        #expect(forward["?"] == ",")
    }
}
