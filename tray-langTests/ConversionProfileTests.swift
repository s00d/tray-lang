import Foundation
import Testing
@testable import tray_lang

/// Each test gets its own UserDefaults suite, so nothing leaks between tests or into the real app settings.
@Suite(.serialized)
struct ConversionProfileTests {
    private func makeDefaults() -> UserDefaults {
        let name = "tray-lang.tests.profiles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func freshInstallUsesAuto() {
        let transformer = TextTransformer(defaults: makeDefaults())
        #expect(transformer.activeProfileID == ConversionProfile.autoID)
        #expect(transformer.activeProfile.isAuto)
        #expect(transformer.customProfiles.isEmpty)
    }

    @Test func selectionPersists() {
        let defaults = makeDefaults()
        let first = TextTransformer(defaults: defaults)
        first.activeProfileID = ConversionProfile.system(target: Layouts.russianPC).id

        let second = TextTransformer(defaults: defaults)
        #expect(second.activeProfileID == "layout:\(Layouts.russianPC)")
        #expect(second.activeProfile.targetLayoutID == Layouts.russianPC)
    }

    @Test func anyInstalledLayoutCanBeSelectedByID() throws {
        let profile = try #require(ConversionProfile.builtIn(id: "layout:com.apple.keylayout.Serbian"))
        #expect(profile.targetLayoutID == "com.apple.keylayout.Serbian")
        #expect(!profile.isEditable)
        #expect(ConversionProfile.builtIn(id: "layout:com.example.missing") == nil)
        #expect(ConversionProfile.builtIn(id: "garbage") == nil)
    }

    @Test func unknownStoredSelectionFallsBackToAuto() {
        let defaults = makeDefaults()
        defaults.set("layout:com.example.removed", forKey: DefaultsKeys.activeProfileID)
        #expect(TextTransformer(defaults: defaults).activeProfileID == ConversionProfile.autoID)
    }

    /// Profiles saved by v1.50 and older: built-ins (isEditable=false) are dropped, custom ones survive.
    @Test func legacyStoredProfilesMigrate() throws {
        let defaults = makeDefaults()
        let customID = UUID().uuidString
        let legacy = """
        [
          {"id":"\(UUID().uuidString)","name":"Russian (QWERTY ↔ ЙЦУКЕН)","isEditable":false,"mapping":{"q":"й"}},
          {"id":"\(customID)","name":"Mine","isEditable":true,"mapping":{"q":"я"}}
        ]
        """
        defaults.set(Data(legacy.utf8), forKey: DefaultsKeys.userProfiles)
        defaults.set(customID, forKey: DefaultsKeys.activeProfileID)

        let transformer = TextTransformer(defaults: defaults)
        #expect(transformer.customProfiles.map(\.name) == ["Mine"])
        #expect(transformer.activeProfileID == customID)
        #expect(transformer.transformText("q") == "я")
    }

    @Test func legacyBuiltInSelectionFallsBackToAuto() {
        let defaults = makeDefaults()
        let oldID = UUID().uuidString
        let legacy = #"[{"id":"\#(oldID)","name":"Russian (QWERTY ↔ ЙЦУКЕН)","isEditable":false,"mapping":{}}]"#
        defaults.set(Data(legacy.utf8), forKey: DefaultsKeys.userProfiles)
        defaults.set(oldID, forKey: DefaultsKeys.activeProfileID)
        #expect(TextTransformer(defaults: defaults).activeProfile.isAuto)
    }

    @Test func corruptStoredProfilesDoNotCrash() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: DefaultsKeys.userProfiles)
        #expect(TextTransformer(defaults: defaults).customProfiles.isEmpty)
    }

    @Test func legacyCustomSymbolsBecomeAProfile() throws {
        let defaults = makeDefaults()
        defaults.set(try JSONEncoder().encode(["a": "ф"]), forKey: DefaultsKeys.customSymbols)
        let transformer = TextTransformer(defaults: defaults)
        #expect(transformer.customProfiles.first?.mapping == ["a": "ф"])
        #expect(defaults.object(forKey: DefaultsKeys.customSymbols) == nil)
    }

    // MARK: Editing custom profiles

    @Test func duplicatingABuiltInCopiesTheMacOSTable() {
        let transformer = TextTransformer(defaults: makeDefaults())
        let copy = transformer.duplicateProfile(.system(target: Layouts.russianMac, name: "Russian"))
        #expect(copy.isEditable)
        #expect(copy.name == "Russian (copy)")
        #expect(copy.mapping == Layouts.resolved(Layouts.russianMac).forward)

        let second = transformer.duplicateProfile(.system(target: Layouts.russianMac, name: "Russian"))
        #expect(second.name == "Russian (copy) 2")
    }

    @Test func editedCustomProfileIsUsedAndSaved() throws {
        let defaults = makeDefaults()
        let transformer = TextTransformer(defaults: defaults)
        var profile = transformer.createEmptyProfile()
        transformer.activeProfileID = profile.id
        #expect(transformer.transformText("abc") == "abc", "empty profile converts nothing")

        profile.mapping = ["a": "ф", "b": "и"]
        transformer.updateProfile(profile)
        #expect(transformer.transformText("ab") == "фи")
        #expect(transformer.transformText("фи") == "ab")

        let reloaded = TextTransformer(defaults: defaults)
        #expect(reloaded.activeProfileID == profile.id)
        #expect(reloaded.transformText("ab") == "фи")
    }

    @Test func editorDraftsAreSavedWithUniqueNames() {
        let transformer = TextTransformer(defaults: makeDefaults())
        let first = transformer.addCustomProfile(.custom(name: "Mine", mapping: ["a": "ф"]))
        let second = transformer.addCustomProfile(.custom(name: "Mine", mapping: ["a": "ф"]))
        let blank = transformer.addCustomProfile(.custom(name: "   ", mapping: ["a": "ф"]))
        #expect(first.name == "Mine")
        #expect(second.name == "Mine 2")
        #expect(blank.name == "My Custom Profile")
        #expect(transformer.mapping(of: first) == ["a": "ф"])
        #expect(transformer.mapping(of: .system(target: Layouts.russianMac)) == Layouts.resolved(Layouts.russianMac).forward)
    }

    @Test func builtInsCannotBeEditedThroughUpdate() {
        let transformer = TextTransformer(defaults: makeDefaults())
        var builtIn = ConversionProfile.system(target: Layouts.russianMac)
        builtIn.mapping = ["a": "z"]
        transformer.updateProfile(builtIn)
        #expect(transformer.customProfiles.isEmpty)
    }

    @Test func deletingTheActiveProfileFallsBackToAuto() {
        let transformer = TextTransformer(defaults: makeDefaults())
        let profile = transformer.createEmptyProfile()
        transformer.activeProfileID = profile.id
        transformer.deleteProfile(id: profile.id)
        #expect(transformer.activeProfile.isAuto)
        #expect(transformer.customProfiles.isEmpty)
    }

    @Test func customProfileGuessesItsLayoutsForSwitching() throws {
        let transformer = TextTransformer(
            profile: .custom(name: "Mine", mapping: ["a": "ф", "s": "ы"]),
            enabledLayouts: { [Layouts.abc, Layouts.russianMac] }
        )
        let resolved = try #require(transformer.resolvedActiveProfile())
        #expect(resolved.sourceLayoutID == Layouts.abc)
        #expect(resolved.targetLayoutID == Layouts.russianMac)
        #expect(transformer.layoutIDToSelect(after: .toTarget) == Layouts.russianMac)
    }

    @Test func encodingRoundTrips() throws {
        let profile = ConversionProfile.custom(name: "X", mapping: ["1": "2"])
        let decoded = try JSONDecoder().decode(ConversionProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }

    @Test func inverseMappingPrefersASCIIKeysOnCollision() {
        let inverse = TextTransformer.inverseMapping(of: ["§": ">", ">": "Ю", "x": ">"])
        #expect(inverse[">"] == "x")
        #expect(inverse["Ю"] == ">")
    }
}
