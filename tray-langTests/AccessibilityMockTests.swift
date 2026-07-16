import Foundation
import Testing
@testable import tray_lang

struct ProcessRuntimeTests {
    @Test func unitTestHostIsDetectedAsRunningUnderTests() {
        #expect(ProcessRuntime.isRunningUnderTests)
        #expect(ProcessRuntime.shouldSkipAccessibilityPrompt)
        #expect(ProcessRuntime.useMockAccessibility)
    }
}

@MainActor
struct AccessibilityManagerMockTests {
    @Test func mockModeNeverPromptsAndStartsDenied() async {
        let manager = AccessibilityManager(usesMock: true)
        #expect(manager.isGranted == false)

        await manager.requestPermissions()
        // Explicit request in mock flips granted without OS dialog
        #expect(manager.isGranted == true)
    }

    @Test func checkStatusInMockDoesNotTouchSystemTrust() {
        let manager = AccessibilityManager(usesMock: true)
        manager.isGranted = false
        manager.checkStatus()
        #expect(manager.isGranted == false)
    }
}
