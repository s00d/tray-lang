import AppKit
import XCTest
@testable import tray_lang

/// ⌘Q / ⌘W hold-to-confirm, driven through the same code the event taps call.
@MainActor
final class HotkeyBlockerTests: XCTestCase {
    private var coordinator: AppCoordinator!
    private var blocker: HotkeyBlockerManager { coordinator.hotkeyBlockerManager }

    override func setUp() async throws {
        AppDefaults.resetForTesting()
        coordinator = AppCoordinator(selectionDriver: FakeTextApp(text: ""))
        blocker.suppressSideEffectsForTesting = true
        blocker.delay = 1
    }

    override func tearDown() async throws {
        coordinator.notificationManager.dismissHUD(animated: false)
        coordinator.stop()
        coordinator = nil
    }

    private func settle(_ seconds: TimeInterval = 0.1) {
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 1)
    }

    func testShortCmdQPressIsBlockedAndCounted() {
        blocker.isCmdQEnabled = true
        let before = blocker.accidentalQuits

        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true))
        XCTAssertTrue(coordinator.notificationManager.isHUDVisible)
        XCTAssertEqual(coordinator.notificationManager.hudText, "Hold ⌘Q to quit")

        // Our own HUD coming to front must not cancel the hold.
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )
        settle(0.05)
        XCTAssertTrue(coordinator.notificationManager.isHUDVisible)

        blocker.handleSyntheticKeyUp(keyCode: 12, commandDown: true)
        settle()
        XCTAssertEqual(blocker.accidentalQuits, before + 1)
        XCTAssertFalse(coordinator.notificationManager.isHUDVisible)
    }

    func testShortCmdWPressIsBlockedAndCounted() {
        blocker.isCmdWEnabled = true
        let before = blocker.accidentalCloses
        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 13, commandDown: true))
        XCTAssertEqual(coordinator.notificationManager.hudText, "Hold ⌘W to close")
        blocker.handleSyntheticKeyUp(keyCode: 13, commandDown: true)
        settle()
        XCTAssertEqual(blocker.accidentalCloses, before + 1)
    }

    func testCompletedHoldIsNotCountedAsAccidental() {
        blocker.isCmdQEnabled = true
        let before = blocker.accidentalQuits
        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true))
        settle(1.15)
        blocker.handleSyntheticKeyUp(keyCode: 12, commandDown: true)
        settle()
        XCTAssertEqual(blocker.accidentalQuits, before)
    }

    func testAutorepeatDoesNotRestartTheHold() {
        blocker.isCmdQEnabled = true
        blocker.delay = 2
        let before = blocker.accidentalQuits
        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true, isAutorepeat: false))
        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true, isAutorepeat: true))
        blocker.handleSyntheticKeyUp(keyCode: 12, commandDown: true)
        settle()
        XCTAssertEqual(blocker.accidentalQuits, before + 1)
    }

    private func cmdQ(down: Bool, flags: CGEventFlags = .maskCommand, marked: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: down)!
        event.flags = flags
        if marked { event.setIntegerValueField(.eventSourceUserData, value: KeystrokeOutput.marker) }
        return event
    }

    /// Whether the tap lets `event` through; the event stays alive for the whole call.
    private func passes(_ type: CGEventType, _ event: CGEvent) -> Bool {
        withExtendedLifetime(event) { blocker.handle(type: type, event: event) != nil }
    }

    func testTapSwallowsQuickCmdQButPassesOurOwnShortcut() {
        blocker.isCmdQEnabled = true
        XCTAssertFalse(passes(.keyDown, cmdQ(down: true)), "real ⌘Q is held back")
        XCTAssertTrue(passes(.keyUp, cmdQ(down: false)))
        XCTAssertTrue(passes(.keyDown, cmdQ(down: true, marked: true)), "the ⌘Q we send after a hold goes through")
    }

    func testOtherModifierCombinationsPassThrough() {
        blocker.isCmdQEnabled = true
        XCTAssertTrue(passes(.keyDown, cmdQ(down: true, flags: [.maskCommand, .maskShift])), "⌘⇧Q (log out) untouched")
        XCTAssertTrue(passes(.keyDown, cmdQ(down: true, flags: [.maskCommand, .maskAlternate])), "⌘⌥Q untouched")
    }

    func testExclusionWorksFromTheFirstPress() throws {
        let frontmost = try XCTUnwrap(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        coordinator.exclusionManager.addExcludedApp(ExcludedApp(name: "Front", bundleID: frontmost, path: ""))
        let fresh = HotkeyBlockerManager(notificationManager: coordinator.notificationManager, exclusionManager: coordinator.exclusionManager)
        fresh.isCmdQEnabled = true
        XCTAssertFalse(fresh.handleSyntheticKeyDown(keyCode: 12, commandDown: true), "excluded app keeps plain ⌘Q without any app switch first")
    }

    func testStartAndStopAreIdempotentWithoutAccess() {
        blocker.isCmdQEnabled = true
        blocker.updateMonitoringState()
        blocker.updateMonitoringState()
        // Tests have no Accessibility: the tap can't be created, protection turns itself off and says why.
        if !blocker.isMonitoring {
            XCTAssertFalse(blocker.isCmdQEnabled)
            XCTAssertNotNil(blocker.startupError)
        }
        blocker.stop()
        blocker.stop()
        XCTAssertFalse(blocker.isMonitoring)
    }

    func testStatisticsReset() {
        blocker.isCmdQEnabled = true
        XCTAssertTrue(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true))
        blocker.handleSyntheticKeyUp(keyCode: 12, commandDown: true)
        settle()
        XCTAssertGreaterThan(blocker.accidentalQuits, 0)
        blocker.resetStatistics()
        XCTAssertEqual(blocker.accidentalQuits, 0)
        XCTAssertEqual(AppDefaults.store.integer(forKey: DefaultsKeys.qblockerAccidentalQuits), 0)
    }

    func testKeysPassThroughWhenDisabledOrWithoutCommand() {
        blocker.isCmdQEnabled = true
        XCTAssertFalse(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: false), "plain Q")
        blocker.isCmdQEnabled = false
        blocker.isCmdWEnabled = false
        XCTAssertFalse(blocker.handleSyntheticKeyDown(keyCode: 12, commandDown: true))
        XCTAssertFalse(blocker.handleSyntheticKeyDown(keyCode: 13, commandDown: true))
    }

    /// When the event taps fail the blocker turns itself off; the settings must show that.
    func testBlockerSwitchingItselfOffIsMirroredToTheUI() {
        coordinator.isCmdQBlockerEnabled = true
        coordinator.isCmdWBlockerEnabled = true
        XCTAssertTrue(blocker.isCmdQEnabled)

        blocker.isCmdQEnabled = false
        blocker.isCmdWEnabled = false
        XCTAssertFalse(coordinator.isCmdQBlockerEnabled)
        XCTAssertFalse(coordinator.isCmdWBlockerEnabled)
    }
}
