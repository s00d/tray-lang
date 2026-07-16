//
//  tray_langApp.swift
//  tray-lang
//

import AppKit
import Combine

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

        existing.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
        coordinator.windowManager.setCoordinator(coordinator)
        coordinator.windowManager.setupStatusBar()

        coordinator.keyboardLayoutManager.$currentLayout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLayout in
                self?.coordinator.windowManager.updateStatusItemTitle(shortName: newLayout?.shortName ?? "")
            }
            .store(in: &cancellables)

        coordinator.start()

        if ProcessInfo.processInfo.arguments.contains("-openSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.coordinator.showMainWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.windowManager.teardownStatusBar()
        coordinator?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        coordinator?.windowManager.teardownStatusBar()
        coordinator?.stop()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
