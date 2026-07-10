import Testing
@testable import tray_lang

struct TextTransformerTests {
    private func russianTransformer() -> TextTransformer {
        let profiles = ConversionProfile.defaultProfiles()
        guard let profile = profiles.first(where: { $0.name == "Russian (QWERTY ↔ ЙЦУКЕН)" }) else {
            fatalError("Russian profile missing")
        }
        return TextTransformer(profiles: profiles, activeProfileID: profile.id)
    }

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

    @Test func doesNotTurnSlashesIntoYuOnSecondPass() {
        let transformer = russianTransformer()
        let url = "https://github.com/s00d/tray-lang"
        let once = transformer.transformText(url)
        let twice = transformer.transformText(once)

        #expect(twice == url)
        #expect(!twice.contains("ю"))
    }
}
