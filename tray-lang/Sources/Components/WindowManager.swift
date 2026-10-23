import SwiftUI
import AppKit

/// Status bar item, its menu, the app's main menu and the settings window.
/// The status menu is rebuilt every time it opens, so it never shows stale state.
@MainActor
final class WindowManager: NSObject, NSMenuDelegate, NSWindowDelegate {
    private var settingsWindow: NSWindow?
    private weak var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?
    private(set) var statusMenu = NSMenu()

    func setCoordinator(_ coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Status item

    func setupStatusBar() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        statusMenu.delegate = self
        item.menu = statusMenu
        statusItem = item
        installMainMenu()
        refreshStatusButton()
    }

    func teardownStatusBar() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    /// Keyboard icon plus the short layout name ("RU", "EN"); the icon changes when conversion can't work.
    func refreshStatusButton() {
        guard let button = statusItem?.button, let coordinator else { return }
        let symbol: String
        if !coordinator.isAccessibilityGranted {
            symbol = "exclamationmark.triangle"
        } else if !coordinator.isTextConversionEnabled {
            symbol = "keyboard.badge.ellipsis"
        } else {
            symbol = "keyboard"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppIdentity.displayName)
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = coordinator.keyboardLayoutManager.currentLayout?.shortName ?? ""
        button.toolTip = AppIdentity.displayName
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        rebuildStatusMenu()
    }

    func rebuildStatusMenu() {
        let menu = statusMenu
        menu.removeAllItems()
        guard let coordinator else { return }
        let transformer = coordinator.textTransformer

        // Input sources, like the system Input menu, so that one can be hidden.
        let layouts = coordinator.keyboardLayoutManager
        let currentID = layouts.currentLayoutID
        for layout in layouts.availableLayouts {
            let entry = item(layout.localizedName, #selector(selectInputSource(_:)), state: layout.id == currentID)
            entry.image = inputSourceIcon(layout)
            entry.representedObject = layout.id
            menu.addItem(entry)
        }
        menu.addItem(item("Open Keyboard Settings…", #selector(openKeyboardSettings), image: "keyboard"))

        // Anything that stops the app from working.
        if !coordinator.isAccessibilityGranted || coordinator.isSecureInputActive {
            menu.addItem(.separator())
        }
        if !coordinator.isAccessibilityGranted {
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccessibility), image: "exclamationmark.triangle"))
        }
        if coordinator.isSecureInputActive {
            let secure = item("Secure Input Is On", #selector(recheckSecureInput), image: "lock.shield")
            secure.toolTip = coordinator.secureInputStatusMessage
            menu.addItem(secure)
        }

        // Text: the three ways of fixing text, and which layouts they use.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Text"))
        let convert = item("Convert Selection", #selector(toggleConversion), state: coordinator.isTextConversionEnabled, image: "character.cursor.ibeam")
        convert.subtitle = coordinator.layoutHotKeyDisplay
        menu.addItem(convert)
        menu.addItem(item("Fix While Typing", #selector(toggleAutoConvert), state: coordinator.isAutoConvertEnabled, image: "wand.and.sparkles"))
        let spelling = item("Fix Spelling", #selector(toggleSpellCheck), state: coordinator.isSpellCheckEnabled, image: "textformat.abc.dottedunderline")
        spelling.subtitle = coordinator.spellCheckHotKeyDisplay
        spelling.isEnabled = coordinator.isTextConversionEnabled
        menu.addItem(spelling)
        let profileItem = item("Layouts", nil, image: "globe")
        profileItem.submenu = profileMenu(transformer)
        profileItem.subtitle = transformer.activeProfile.isAuto ? "Auto" : transformer.activeProfile.name
        menu.addItem(profileItem)

        // Apps: per-app layout and quit protection.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Apps"))
        menu.addItem(item("Layout per App", #selector(toggleSmartLayout), state: coordinator.smartLayoutManager.isEnabled, image: "macwindow.on.rectangle"))
        menu.addItem(item("Hold ⌘Q to Quit", #selector(toggleCmdQ), state: coordinator.isCmdQBlockerEnabled, image: "power"))
        menu.addItem(item("Hold ⌘W to Close", #selector(toggleCmdW), state: coordinator.isCmdWBlockerEnabled, image: "xmark.square"))

        menu.addItem(.separator())
        let settings = item("Settings…", #selector(showSettings), image: "gearshape")
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(item("About \(AppIdentity.displayName)", #selector(showAbout), image: "info.circle"))
        let quit = NSMenuItem(title: "Quit \(AppIdentity.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: nil)
        menu.addItem(quit)
    }

    /// Auto, the user's input sources, the other common layouts in a submenu, custom profiles.
    private func profileMenu(_ transformer: TextTransformer) -> NSMenu {
        let menu = NSMenu()
        let enabled = Set(SystemKeyboardLayouts.enabledLayoutIDs())
        func entry(_ profile: ConversionProfile) -> NSMenuItem {
            let entry = item(profile.isAuto ? "Auto" : profile.name, #selector(selectProfile(_:)), state: profile.id == transformer.activeProfileID)
            entry.representedObject = profile.id
            return entry
        }

        let builtIns = transformer.builtInProfiles()
        menu.addItem(entry(.auto))
        let yours = builtIns.filter { $0.targetLayoutID.map(enabled.contains) == true }
        if !yours.isEmpty {
            menu.addItem(.sectionHeader(title: "Your Input Sources"))
            yours.forEach { menu.addItem(entry($0)) }
        }
        let others = builtIns.filter { !$0.isAuto && $0.targetLayoutID.map(enabled.contains) != true }
        let active = transformer.activeProfile
        let more = item("Other Layouts", nil, state: others.contains { $0.id == active.id })
        more.submenu = NSMenu()
        others.forEach { more.submenu?.addItem(entry($0)) }
        menu.addItem(more)

        if !transformer.customProfiles.isEmpty {
            menu.addItem(.sectionHeader(title: "Custom"))
            transformer.customProfiles.forEach { menu.addItem(entry($0)) }
        }
        menu.addItem(.separator())
        menu.addItem(item("Edit Profiles…", #selector(showSettings)))
        return menu
    }

    private func item(_ title: String, _ action: Selector?, state: Bool? = nil, image: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if action != nil { item.target = self }
        if let state { item.state = state ? .on : .off }
        if let image { item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil) }
        return item
    }

    // MARK: - Menu actions

    @objc private func toggleConversion() { coordinator?.isTextConversionEnabled.toggle() }
    @objc private func toggleSpellCheck() { coordinator?.isSpellCheckEnabled.toggle() }
    @objc private func toggleAutoConvert() { coordinator?.isAutoConvertEnabled.toggle() }
    @objc private func toggleSmartLayout() { coordinator?.smartLayoutManager.isEnabled.toggle() }
    @objc private func toggleCmdQ() { coordinator?.isCmdQBlockerEnabled.toggle() }
    @objc private func toggleCmdW() { coordinator?.isCmdWBlockerEnabled.toggle() }
    @objc private func recheckSecureInput() { coordinator?.recheckSecureInput() }

    @objc private func selectInputSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        coordinator?.keyboardLayoutManager.switchToLayout(id: id)
    }

    @objc private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private var inputSourceIcons: [String: NSImage] = [:]

    /// macOS's own icon for the layout (flag or letters), loaded once.
    private func inputSourceIcon(_ layout: KeyboardLayout) -> NSImage? {
        if let cached = inputSourceIcons[layout.id] { return cached }
        guard let url = layout.iconURL, let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        }
        image.size = NSSize(width: 16, height: 16)
        inputSourceIcons[layout.id] = image
        return image
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        coordinator?.textTransformer.activeProfileID = id
    }

    @objc private func grantAccessibility() {
        guard let coordinator else { return }
        Task { await coordinator.accessibilityManager.requestPermissions(openSettings: true) }
    }

    @objc func showSettings() {
        presentSettingsWindow()
    }

    @objc func showAbout() {
        NSApp.activate()
        let credits = NSAttributedString(
            string: "github.com/s00d/tray-lang",
            attributes: [.link: URL(string: "https://github.com/s00d/tray-lang")!, .font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Main menu (makes ⌘C/⌘V/⌘A/⌘W work in the settings window)

    func installMainMenu() {
        let main = NSMenu()
        let name = AppIdentity.displayName

        let appMenu = NSMenu()
        appMenu.addItem(item("About \(name)", #selector(showAbout)))
        appMenu.addItem(.separator())
        let settings = item("Settings…", #selector(showSettings))
        settings.keyEquivalent = ","
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))

        for (title, submenu) in [(name, appMenu), ("Edit", editMenu), ("Window", windowMenu)] {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = submenu
            main.addItem(holder)
        }
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Settings window

    var settingsWindowForTesting: NSWindow? { settingsWindow }
    var statusButtonForTesting: NSStatusBarButton? { statusItem?.button }

    private func presentSettingsWindow() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        // An accessory app's windows open behind the active app; be a regular app (Dock icon) while settings are open.
        if !ProcessRuntime.isRunningUnderTests {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func createSettingsWindow() {
        guard let coordinator else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "\(AppIdentity.displayName) Settings"
        window.identifier = NSUserInterfaceItemIdentifier("tray-lang.settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView(coordinator: coordinator))
        window.setContentSize(NSSize(width: 760, height: 540))
        window.setFrameAutosaveName("tray-lang.settings")
        window.center()
        settingsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.textTransformer.saveProfiles()
        if !ProcessRuntime.isRunningUnderTests {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
