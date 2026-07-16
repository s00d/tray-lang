import AppKit
import SwiftUI
import XCTest
@testable import tray_lang

@MainActor
final class SettingsWindowTests: XCTestCase {
    private var coordinator: AppCoordinator!

    override func setUp() async throws {
        coordinator = AppCoordinator()
        XCTAssertTrue(ProcessRuntime.useMockAccessibility)
        XCTAssertFalse(coordinator.accessibilityManager.isGranted)
    }

    override func tearDown() async throws {
        coordinator?.windowManager.teardownStatusBar()
        coordinator?.stop()
        if let window = coordinator?.windowManager.settingsWindowForTesting {
            window.orderOut(nil)
            window.contentViewController = nil
        }
        coordinator = nil
    }

    func testContentViewCanLayoutInHostingControllerWithoutCrashing() {
        let hostingController = NSHostingController(rootView: ContentView(coordinator: coordinator))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController

        hostingController.view.frame = window.contentView?.bounds ?? .zero
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()

        XCTAssertFalse(hostingController.view.inLiveResize)
        XCTAssertGreaterThan(hostingController.view.bounds.width, 0)
        XCTAssertGreaterThan(hostingController.view.bounds.height, 0)
    }

    func testWindowManagerCreatesSettingsWindow() {
        coordinator.windowManager.setCoordinator(coordinator)
        let initialPolicy = NSApp.activationPolicy()
        coordinator.showMainWindow()

        let settingsWindow = coordinator.windowManager.settingsWindowForTesting
        XCTAssertNotNil(settingsWindow)
        XCTAssertEqual(settingsWindow?.identifier?.rawValue, "tray-lang.settings")
        XCTAssertNotNil(settingsWindow?.contentViewController)
        XCTAssertEqual(NSApp.activationPolicy(), initialPolicy)
    }

    func testRefreshStatusMenuStateUpdatesCheckmarks() {
        let windowManager = coordinator.windowManager
        windowManager.setCoordinator(coordinator)
        windowManager.setupStatusBar()

        coordinator.isSmartLayoutEnabled = true
        windowManager.menuWillOpen(NSMenu())

        XCTAssertEqual(windowManager.smartLayoutMenuItemStateForTesting, .on)
    }

    func testShowMainWindowDoesNotChangeActivationPolicy() {
        coordinator.windowManager.setCoordinator(coordinator)
        coordinator.windowManager.setupStatusBar()

        let policyBefore = NSApp.activationPolicy()
        coordinator.showMainWindow()

        XCTAssertEqual(NSApp.activationPolicy(), policyBefore)
        XCTAssertNotNil(coordinator.windowManager.settingsWindowForTesting)
    }

    func testCoordinatorDoesNotForwardHotKeyManagerObjectWillChange() {
        var publishCount = 0
        let cancellable = coordinator.objectWillChange.sink {
            publishCount += 1
        }

        coordinator.hotKeyManager.isSecureInputActive.toggle()
        coordinator.hotKeyManager.isSecureInputActive.toggle()

        XCTAssertEqual(publishCount, 0, "Nested manager updates must not re-publish coordinator during layout")
        _ = cancellable
    }

    func testMockAccessibilityDoesNotAutoStartBlockerTaps() {
        XCTAssertFalse(coordinator.hotkeyBlockerManager.isMonitoring)
        XCTAssertFalse(coordinator.hotKeyManager.isEnabled)
    }
}
