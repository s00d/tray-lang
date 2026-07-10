import AppKit
import SwiftUI
import XCTest
@testable import tray_lang

@MainActor
final class SettingsWindowTests: XCTestCase {

    func testContentViewCanLayoutInHostingControllerWithoutCrashing() {
        let coordinator = AppCoordinator()
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
        let coordinator = AppCoordinator()
        coordinator.windowManager.setCoordinator(coordinator)
        let initialPolicy = NSApp.activationPolicy()
        coordinator.showMainWindow()

        let expectation = expectation(description: "settings window appears")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let settingsWindow = NSApp.windows.first { $0.title == "Tray Lang" }
            XCTAssertNotNil(settingsWindow)
            XCTAssertTrue(settingsWindow?.isVisible == true)
            XCTAssertEqual(NSApp.activationPolicy(), initialPolicy)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testRefreshStatusMenuStateUpdatesCheckmarks() {
        let coordinator = AppCoordinator()
        let windowManager = coordinator.windowManager
        windowManager.setCoordinator(coordinator)
        windowManager.setupStatusBar()

        coordinator.isSmartLayoutEnabled = true
        windowManager.menuWillOpen(NSMenu())

        XCTAssertEqual(windowManager.smartLayoutMenuItemStateForTesting, .on)
    }

    func testShowMainWindowDoesNotChangeActivationPolicy() {
        let coordinator = AppCoordinator()
        coordinator.windowManager.setCoordinator(coordinator)
        coordinator.windowManager.setupStatusBar()

        let policyBefore = NSApp.activationPolicy()
        coordinator.showMainWindow()

        let expectation = expectation(description: "policy unchanged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(NSApp.activationPolicy(), policyBefore)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testCoordinatorDoesNotForwardHotKeyManagerObjectWillChange() {
        let coordinator = AppCoordinator()
        var publishCount = 0
        let cancellable = coordinator.objectWillChange.sink {
            publishCount += 1
        }

        coordinator.hotKeyManager.isSecureInputActive.toggle()
        coordinator.hotKeyManager.isSecureInputActive.toggle()

        XCTAssertEqual(publishCount, 0, "Nested manager updates must not re-publish coordinator during layout")
        _ = cancellable
    }
}
