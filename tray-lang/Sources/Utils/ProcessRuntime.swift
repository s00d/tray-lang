import Foundation

enum ProcessRuntime {
    /// Unit-test host (`xctest` / `tray-lang.app` as TEST_HOST).
    static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// UI tests and local overrides. Pass `-skipAccessibilityPrompt` in launchArguments.
    static var shouldSkipAccessibilityPrompt: Bool {
        if isRunningUnderTests { return true }
        return ProcessInfo.processInfo.arguments.contains("-skipAccessibilityPrompt")
    }

    /// Prefer mocked accessibility state in automated runs (no system dialogs / event taps).
    static var useMockAccessibility: Bool {
        shouldSkipAccessibilityPrompt
    }
}
