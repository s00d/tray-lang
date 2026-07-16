import SwiftUI
import AppKit

// MARK: - NSImage Extension
extension NSImage {
    func withTintColor(_ color: NSColor) -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return self
        }

        return NSImage(size: size, flipped: false) { bounds in
            color.setFill()
            bounds.fill()

            let imageRect = NSRect(origin: .zero, size: self.size)
            self.draw(in: imageRect, from: imageRect, operation: .destinationIn, fraction: 1.0)

            return true
        }
    }
}

// MARK: - Window Manager
@MainActor
final class WindowManager: NSObject, NSMenuDelegate {
    private var mainWindow: NSWindow?
    private var hostingController: NSHostingController<ContentView>?
    private var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    private var autoLaunchMenuItem: NSMenuItem?
    private var smartLayoutMenuItem: NSMenuItem?

    func setCoordinator(_ coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }

        button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tray Lang")
        button.imagePosition = .imageLeft

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusMenu = menu

        let openSettingsItem = menu.addItem(
            withTitle: "Open Settings",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        openSettingsItem.target = self
        menu.addItem(.separator())

        autoLaunchMenuItem = menu.addItem(
            withTitle: "Auto Launch",
            action: #selector(toggleAutoLaunch),
            keyEquivalent: ""
        )
        autoLaunchMenuItem?.target = self

        smartLayoutMenuItem = menu.addItem(
            withTitle: "Smart Layout",
            action: #selector(toggleSmartLayout),
            keyEquivalent: ""
        )
        smartLayoutMenuItem?.target = self

        menu.addItem(.separator())

        let aboutItem = menu.addItem(
            withTitle: "About...",
            action: #selector(showAboutWindow),
            keyEquivalent: ""
        )
        aboutItem.target = self

        let quitItem = menu.addItem(
            withTitle: "Quit Tray Lang",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self

        item.menu = menu
    }

    func updateStatusItemTitle(shortName: String) {
        statusItem?.button?.title = shortName
    }

    func updateStatusItemIcon(isEnabled: Bool = true) {
        guard let button = statusItem?.button else { return }

        if !isEnabled {
            button.image = NSImage(systemSymbolName: "keyboard.slash", accessibilityDescription: "Tray Lang Disabled")
            button.image?.isTemplate = true
        } else {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tray Lang")
            button.image?.isTemplate = true
        }
    }

    func refreshStatusMenuState() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let coordinator else { return }

        autoLaunchMenuItem?.state = coordinator.autoLaunchManager.isAutoLaunchEnabled() ? .on : .off
        smartLayoutMenuItem?.state = coordinator.isSmartLayoutEnabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenuState()
    }

    var smartLayoutMenuItemStateForTesting: NSControl.StateValue {
        smartLayoutMenuItem?.state ?? .off
    }

    /// Exposed for unit tests — `NSApp.windows` / `isVisible` are unreliable under TEST_HOST + `.accessory`.
    var settingsWindowForTesting: NSWindow? { mainWindow }

    // MARK: - Menu Actions

    @objc func showMainWindow() {
        presentMainWindow()
    }

    @objc func toggleAutoLaunch() {
        guard let coordinator else { return }
        coordinator.isAutoLaunchEnabled.toggle()
        refreshStatusMenuState()
    }

    @objc func toggleSmartLayout() {
        guard let coordinator else { return }
        coordinator.isSmartLayoutEnabled.toggle()
        refreshStatusMenuState()
    }

    @objc func showAboutWindow() {
        presentMainWindow()
        NotificationCenter.default.post(name: .showAboutWindow, object: nil)
    }

    @objc func quitApp() {
        teardownStatusBar()
        NSApp.terminate(nil)
    }

    func teardownStatusBar() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        statusMenu = nil
        autoLaunchMenuItem = nil
        smartLayoutMenuItem = nil
    }

    // MARK: - Main Window

    private func presentMainWindow() {
        if mainWindow == nil {
            createMainWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func createMainWindow() {
        guard let coordinator else { return }

        let contentView = ContentView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = AppIdentity.displayName
        window.identifier = NSUserInterfaceItemIdentifier("tray-lang.settings")
        window.delegate = self
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 800, height: 500))
        window.center()

        mainWindow = window
    }
}

// MARK: - NSWindowDelegate
extension WindowManager: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == mainWindow else { return }

        window.contentViewController = nil
        hostingController = nil
        mainWindow = nil
        debugLog("🧹 WindowManager: Окно закрыто и очищено от retain cycles")
    }
}
