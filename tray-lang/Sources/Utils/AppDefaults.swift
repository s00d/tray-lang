import Foundation

enum AppDefaults {
    private static let testSuiteName = "tray-lang.tests"

    /// Real settings for the app; a throwaway suite under tests so runs never touch the user's settings.
    static let store: UserDefaults = {
        guard ProcessRuntime.isRunningUnderTests, let suite = UserDefaults(suiteName: testSuiteName) else {
            return .standard
        }
        suite.removePersistentDomain(forName: testSuiteName)
        return suite
    }()

    /// Tests: start from empty settings.
    static func resetForTesting() {
        guard ProcessRuntime.isRunningUnderTests else { return }
        store.removePersistentDomain(forName: testSuiteName)
    }
}
