//
//  tray_langApp.swift
//  tray-lang
//

import AppKit

@main
final class TrayLangApplication {
    static func main() {
        guard SingleInstanceGuard.activateExistingInstanceIfNeeded() == false else {
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum SingleInstanceGuard {
    @discardableResult
    static func activateExistingInstanceIfNeeded() -> Bool {
        if ProcessRuntime.isRunningUnderTests {
            return false
        }

        guard let bundleID = Bundle.main.bundleIdentifier else { return false }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = others.first else { return false }

        existing.activate(from: .current, options: [.activateAllWindows])
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted by the app: they build their own coordinators, so no tray, windows or taps here.
        guard !ProcessRuntime.isRunningUnderTests else { return }

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.windowManager.setupStatusBar()
        coordinator.start()

        if ProcessInfo.processInfo.arguments.contains("-openSettings") {
            coordinator.windowManager.showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.windowManager.showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.windowManager.teardownStatusBar()
        coordinator?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
