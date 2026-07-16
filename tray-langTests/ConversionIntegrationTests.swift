import AppKit
import XCTest
@testable import tray_lang

@MainActor
final class ConversionIntegrationTests: XCTestCase {
    private var coordinator: AppCoordinator!
    private var fixture: ConversionFixtureWindow!

    private func grantAccessibilityForTesting(withoutStartingTaps: Bool = true) {
        if withoutStartingTaps {
            // Avoid CGEvent.tapCreate when mock grant flips to true
            coordinator.isCmdQBlockerEnabled = false
            coordinator.isCmdWBlockerEnabled = false
            coordinator.isTextConversionEnabled = false
            coordinator.hotkeyBlockerManager.isCmdQEnabled = false
            coordinator.hotkeyBlockerManager.isCmdWEnabled = false
        }
        coordinator.accessibilityManager.isGranted = true
        // Sink updates isAccessibilityGranted on main
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(coordinator.isAccessibilityGranted)
    }

    override func setUp() async throws {
        coordinator = AppCoordinator()
        HUDAlertManager.shared.dismissHUD(fade: false)
    }

    override func tearDown() async throws {
        if let fixture, let coordinator {
            fixture.uninstallSelectionBridge(from: coordinator.textProcessingManager)
        }
        fixture?.close()
        fixture = nil
        HUDAlertManager.shared.dismissHUD(fade: false)
        coordinator?.hotkeyBlockerManager.suppressSideEffectsForTesting = false
        coordinator?.stop()
        coordinator = nil
    }

    // MARK: - HUD

    func testTriggerConversionShowsHUDWhenAccessibilityGranted() {
        grantAccessibilityForTesting()

        coordinator.triggerConversionForTesting(.changeLayout)

        XCTAssertTrue(coordinator.notificationManager.isHUDVisibleForTesting)
        XCTAssertEqual(coordinator.notificationManager.hudTextForTesting, "Converting layout...")

        // Allow async processSelectedText to start/finish
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        HUDAlertManager.shared.dismissHUD(fade: false)
        XCTAssertFalse(coordinator.notificationManager.isHUDVisibleForTesting)
    }

    func testTriggerSpellCheckShowsHUDWhenGranted() {
        grantAccessibilityForTesting()
        coordinator.triggerConversionForTesting(.fixSpelling)

        XCTAssertTrue(coordinator.notificationManager.isHUDVisibleForTesting)
        XCTAssertEqual(coordinator.notificationManager.hudTextForTesting, "Fixing spelling...")
        HUDAlertManager.shared.dismissHUD(fade: false)
    }

    func testTriggerConversionWithoutGrantDoesNotShowConversionHUD() {
        coordinator.accessibilityManager.isGranted = false
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(coordinator.isAccessibilityGranted)

        HUDAlertManager.shared.dismissHUD(fade: false)
        coordinator.triggerConversionForTesting(.changeLayout)

        XCTAssertFalse(
            coordinator.notificationManager.isHUDVisibleForTesting,
            "Denied path must not show conversion HUD (alert is suppressed under tests)"
        )
    }

    // MARK: - Fixture conversion (in-process bridge — no system Accessibility)

    func testTextFieldConversionViaProcessSelectedText() {
        grantAccessibilityForTesting()

        let profiles = coordinator.textTransformer.profiles
        guard let russian = profiles.first(where: { $0.name == "Russian (QWERTY ↔ ЙЦУКЕН)" }) else {
            return XCTFail("Russian profile missing")
        }
        coordinator.textTransformer.activeProfileID = russian.id

        fixture = ConversionFixtureWindow(mode: .textField)
        fixture.show(withText: "пше")
        fixture.selectAll()
        fixture.installSelectionBridge(on: coordinator.textProcessingManager)

        let expected = coordinator.textTransformer.transformText("пше")
        XCTAssertEqual(expected, "git")

        coordinator.textProcessingManager.processSelectedText(action: .changeLayout)
        fixture.pumpRunLoop(for: 0.05)

        XCTAssertEqual(fixture.currentText, expected, "Selected text in fixture field should convert")
    }

    func testTextViewRoundTripViaTriggerConversion() {
        grantAccessibilityForTesting()
        let profiles = coordinator.textTransformer.profiles
        guard let russian = profiles.first(where: { $0.name == "Russian (QWERTY ↔ ЙЦУКЕН)" }) else {
            return XCTFail("Russian profile missing")
        }
        coordinator.textTransformer.activeProfileID = russian.id

        fixture = ConversionFixtureWindow(mode: .textView)
        fixture.show(withText: "git")
        fixture.selectAll()
        fixture.installSelectionBridge(on: coordinator.textProcessingManager)

        coordinator.triggerConversionForTesting(.changeLayout)
        // triggerConversion schedules processSelectedText asynchronously
        fixture.pumpRunLoop(for: 0.2)

        XCTAssertEqual(fixture.currentText, "пше")
        XCTAssertFalse(
            coordinator.notificationManager.isHUDVisibleForTesting,
            "HUD should be dismissed after processing finishes"
        )

        // Second pass restores Latin
        fixture.selectAll()
        coordinator.triggerConversionForTesting(.changeLayout)
        fixture.pumpRunLoop(for: 0.2)
        XCTAssertEqual(fixture.currentText, "git")
    }

    func testWebViewModeIsSkippedPlaceholder() throws {
        fixture = ConversionFixtureWindow(mode: .webView)
        try XCTSkipIf(fixture.isWebViewMode, "WebView AX selection is not covered in this phase")
    }

    // MARK: - Blocker synthetic keys

    func testSyntheticCmdQShortPressIncrementsAccidentalQuits() {
        let blocker = coordinator.hotkeyBlockerManager
        blocker.suppressSideEffectsForTesting = true
        blocker.isCmdQEnabled = true
        blocker.delay = 1

        let before = blocker.accidentalQuits

        let swallowed = blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true)
        XCTAssertTrue(swallowed)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(coordinator.notificationManager.isHUDVisibleForTesting)

        // Early release before hold completes
        blocker.handleSyntheticKeyUp(keyCode: 12, commandDown: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        // accidentalQuits updates on main async
        let expectation = expectation(description: "accidental quit counter")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(blocker.accidentalQuits, before + 1)
        XCTAssertFalse(coordinator.notificationManager.isHUDVisibleForTesting)
    }

    func testSyntheticCmdWShortPressIncrementsAccidentalCloses() {
        let blocker = coordinator.hotkeyBlockerManager
        blocker.suppressSideEffectsForTesting = true
        blocker.isCmdWEnabled = true
        blocker.delay = 1

        let before = blocker.accidentalCloses

        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 13, commandDown: true))
        blocker.handleSyntheticKeyUp(keyCode: 13, commandDown: true)

        let expectation = expectation(description: "accidental close counter")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(blocker.accidentalCloses, before + 1)
    }

    func testSyntheticCmdQHoldLongEnoughDoesNotCountAsAccidental() {
        let blocker = coordinator.hotkeyBlockerManager
        blocker.suppressSideEffectsForTesting = true
        blocker.isCmdQEnabled = true
        blocker.delay = 1

        let before = blocker.accidentalQuits

        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true))

        // Wait for hold timer to complete (suppressSideEffects skips terminate)
        let holdExpectation = expectation(description: "hold completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            holdExpectation.fulfill()
        }
        wait(for: [holdExpectation], timeout: 2)

        blocker.handleSyntheticKeyUp(keyCode: 12, commandDown: true)

        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settle.fulfill()
        }
        wait(for: [settle], timeout: 1)

        XCTAssertEqual(blocker.accidentalQuits, before, "Completed hold must not log accidental quit")
    }

    func testSyntheticAutorepeatDoesNotRestartHold() {
        let blocker = coordinator.hotkeyBlockerManager
        blocker.suppressSideEffectsForTesting = true
        blocker.isCmdQEnabled = true
        blocker.delay = 2

        let before = blocker.accidentalQuits

        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true, isAutorepeat: false))
        // Autorepeat while holding — must stay swallowed, not reset timer / double-count
        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true, isAutorepeat: true))

        blocker.handleSyntheticKeyUp(keyCode: 12, commandDown: true)

        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settle.fulfill()
        }
        wait(for: [settle], timeout: 1)

        XCTAssertEqual(blocker.accidentalQuits, before + 1)
    }

    func testSyntheticWithoutCommandPassesThrough() {
        let blocker = coordinator.hotkeyBlockerManager
        blocker.isCmdQEnabled = true
        XCTAssertFalse(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: false))
    }
}
