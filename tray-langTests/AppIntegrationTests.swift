import AppKit
import SwiftUI
import XCTest
@testable import tray_lang

/// Coordinator + menu + settings, with a fake target app instead of the real Accessibility / clipboard.
@MainActor
final class AppIntegrationTests: XCTestCase {
    private var app: FakeTextApp!
    private var coordinator: AppCoordinator!

    override func setUp() async throws {
        AppDefaults.resetForTesting()
        app = FakeTextApp(text: "ghbdtn")
        coordinator = AppCoordinator(selectionDriver: app)
        // Global hotkeys and event taps stay off: tests must not grab the user's real ⌘1 or ⌘Q.
        coordinator.isTextConversionEnabled = false
        coordinator.isCmdQBlockerEnabled = false
        coordinator.isCmdWBlockerEnabled = false
        coordinator.textTransformer.activeProfileID = ConversionProfile.system(target: Layouts.russianMac).id
    }

    override func tearDown() async throws {
        coordinator.notificationManager.dismissHUD(animated: false)
        coordinator.stop()
        coordinator = nil
        app = nil
    }

    private func grantAccessibility() {
        coordinator.accessibilityManager.isGranted = true
        XCTAssertTrue(coordinator.isAccessibilityGranted)
    }

    private func pump(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: Hotkey → conversion

    func testHotkeyConvertsSelectionWithoutPopup() {
        grantAccessibility()
        coordinator.triggerConversionForTesting(.changeLayout)
        XCTAssertEqual(app.text, "привет")
        XCTAssertFalse(coordinator.notificationManager.isHUDVisible, "no popup for a normal conversion")

        coordinator.triggerConversionForTesting(.changeLayout)
        pump()
        XCTAssertEqual(app.text, "ghbdtn", "second press converts back")
    }

    func testHotkeyWithoutAccessibilityExplainsAndDoesNothing() {
        coordinator.accessibilityManager.isGranted = false
        coordinator.triggerConversionForTesting(.changeLayout)
        XCTAssertEqual(coordinator.notificationManager.hudText, "Accessibility access needed")
        pump()
        XCTAssertEqual(app.text, "ghbdtn")
        XCTAssertEqual(app.axWriteCount, 0)
    }

    func testSpellCheckHotkeyIgnoredWhenDisabled() {
        grantAccessibility()
        coordinator.isSpellCheckEnabled = false
        app.text = "teh"
        app.selection = app.text.startIndex..<app.text.endIndex
        NotificationCenter.default.post(name: .spellCheckHotKeyPressed, object: nil)
        pump()
        XCTAssertEqual(app.text, "teh")
    }

    // MARK: Settings persistence (isolated test suite, never the real app domain)

    func testSettingsUseIsolatedDefaults() {
        XCTAssertNotEqual(AppDefaults.store, UserDefaults.standard)
    }

    func testTogglesPersist() {
        coordinator.isSpellCheckEnabled = true
        coordinator.isTextConversionEnabled = true
        coordinator.isTextConversionEnabled = false
        XCTAssertEqual(AppDefaults.store.object(forKey: DefaultsKeys.spellCheckEnabled) as? Bool, true)
        XCTAssertEqual(AppDefaults.store.object(forKey: DefaultsKeys.hotKeyMonitoringEnabled) as? Bool, false)

        coordinator.blockerDelay = 3
        XCTAssertEqual(AppDefaults.store.integer(forKey: DefaultsKeys.qblockerDelay), 3)
        XCTAssertEqual(coordinator.hotkeyBlockerManager.delay, 3)
    }

    // MARK: Status menu

    private func menuItem(_ title: String, in menu: NSMenu? = nil) -> NSMenuItem? {
        (menu ?? coordinator.windowManager.statusMenu).items.first { $0.title == title }
    }

    private func click(_ item: NSMenuItem?) {
        guard let item, let action = item.action else { return XCTFail("missing menu item") }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    func testStatusMenuShowsCurrentState() throws {
        coordinator.isSpellCheckEnabled = true
        coordinator.windowManager.rebuildStatusMenu()

        let titles = coordinator.windowManager.statusMenu.items.map(\.title)
        for title in ["Convert Selection", "Fix While Typing", "Fix Spelling", "Layouts", "Layout per App", "Hold ⌘Q to Quit", "Hold ⌘W to Close", "Settings…", "Quit \(AppIdentity.displayName)"] {
            XCTAssertTrue(titles.contains(title), "missing \(title) in \(titles)")
        }
        XCTAssertTrue(titles.contains("Grant Accessibility Access…"), "AX not granted in tests")
        let sources = coordinator.windowManager.statusMenu.items.filter { ($0.representedObject as? String)?.hasPrefix("com.apple.") == true }
        XCTAssertEqual(sources.count, coordinator.keyboardLayoutManager.availableLayouts.count, "every input source is listed, like the system Input menu")
        XCTAssertEqual(sources.filter { $0.state == .on }.count, 1, "the current one is checked")
        XCTAssertTrue(titles.contains("Open Keyboard Settings…"))
        let items = coordinator.windowManager.statusMenu.items
        XCTAssertFalse(zip(items, items.dropFirst()).contains { $0.isSeparatorItem && $1.isSeparatorItem }, "no double separators")
        XCTAssertEqual(menuItem("Convert Selection")?.state, .off)
        XCTAssertEqual(menuItem("Fix While Typing")?.state, .off, "auto-convert is off by default")
        XCTAssertTrue(coordinator.windowManager.statusMenu.items.filter { !$0.isSeparatorItem && !$0.isSectionHeader }.allSatisfy { $0.image != nil }, "every item has an icon")
        XCTAssertEqual(menuItem("Fix Spelling")?.state, .on)
        XCTAssertEqual(menuItem("Convert Selection")?.subtitle, coordinator.layoutHotKeyDisplay)
        XCTAssertEqual(menuItem("Settings…")?.keyEquivalent, ",")

        grantAccessibility()
        coordinator.windowManager.rebuildStatusMenu()
        XCTAssertNil(menuItem("Grant Accessibility Access…"))
    }

    func testStatusMenuTogglesSettings() {
        coordinator.windowManager.rebuildStatusMenu()
        XCTAssertEqual(menuItem("Fix Spelling")?.isEnabled, false, "spelling needs conversion on")

        click(menuItem("Convert Selection"))
        XCTAssertTrue(coordinator.isTextConversionEnabled)
        coordinator.windowManager.rebuildStatusMenu()
        XCTAssertEqual(menuItem("Fix Spelling")?.isEnabled, true)
        click(menuItem("Fix Spelling"))
        XCTAssertTrue(coordinator.isSpellCheckEnabled)

        click(menuItem("Fix While Typing"))
        XCTAssertTrue(coordinator.isAutoConvertEnabled)
        XCTAssertEqual(AppDefaults.store.object(forKey: DefaultsKeys.autoConvertEnabled) as? Bool, true)
        XCTAssertFalse(coordinator.autoConvertManager.isMonitoring, "no key monitor without Accessibility, and never under tests")

        click(menuItem("Layout per App"))
        XCTAssertTrue(coordinator.smartLayoutManager.isEnabled)
        click(menuItem("Layout per App"))
        XCTAssertFalse(coordinator.smartLayoutManager.isEnabled)

        coordinator.windowManager.rebuildStatusMenu()
        XCTAssertEqual(menuItem("Fix Spelling")?.state, .on)
    }

    func testProfileSubmenuSelectsProfile() throws {
        coordinator.windowManager.rebuildStatusMenu()
        let submenu = try XCTUnwrap(menuItem("Layouts")?.submenu)
        let entries = submenu.items + (submenu.items.first { $0.title == "Other Layouts" }?.submenu?.items ?? [])
        let profiles = entries.filter { $0.representedObject is String }
        XCTAssertEqual(profiles.first?.title, "Auto")
        XCTAssertEqual(profiles.filter { $0.state == .on }.count, 1)

        let pcItem = try XCTUnwrap(profiles.first { ($0.representedObject as? String) == "layout:\(Layouts.russianPC)" })
        click(pcItem)
        XCTAssertEqual(coordinator.textTransformer.activeProfileID, "layout:\(Layouts.russianPC)")
    }

    // MARK: Settings window

    func testSettingsWindowOpensWithoutChangingActivationPolicyUnderTests() throws {
        let policy = NSApp.activationPolicy()
        coordinator.windowManager.showSettings()
        let window = try XCTUnwrap(coordinator.windowManager.settingsWindowForTesting)
        XCTAssertEqual(window.identifier?.rawValue, "tray-lang.settings")
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertEqual(NSApp.activationPolicy(), policy)
        window.close()
    }

    func testEveryPaneLaysOut() {
        let panes: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettingsView(coordinator: coordinator))),
            ("conversion", AnyView(ConversionSettingsView(transformer: coordinator.textTransformer))),
            ("smart", AnyView(SmartLayoutSettingsView(smartLayoutManager: coordinator.smartLayoutManager, keyboardLayoutManager: coordinator.keyboardLayoutManager))),
            ("protection", AnyView(ProtectionSettingsView(coordinator: coordinator, exclusionManager: coordinator.exclusionManager, blocker: coordinator.hotkeyBlockerManager))),
            ("root", AnyView(SettingsView(coordinator: coordinator))),
        ]
        for (name, view) in panes {
            let host = NSHostingView(rootView: view.frame(width: 700, height: 500))
            host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0, name)
        }
    }

    func testStatusButtonShowsIconAndLayout() throws {
        coordinator.windowManager.setupStatusBar()
        defer { coordinator.windowManager.teardownStatusBar() }
        let button = try XCTUnwrap(coordinator.windowManager.statusButtonForTesting)
        XCTAssertNotNil(button.image, "icon next to the layout name")
        XCTAssertTrue(button.image?.isTemplate == true)
        XCTAssertEqual(button.title, coordinator.keyboardLayoutManager.currentLayout?.shortName ?? "")
    }

    func testMainMenuHasEditCommands() throws {
        coordinator.windowManager.installMainMenu()
        let edit = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
        let keys = edit.items.map(\.keyEquivalent)
        for key in ["x", "c", "v", "a", "z"] {
            XCTAssertTrue(keys.contains(key), "⌘\(key) missing")
        }
    }
}

final class HotKeyTests: XCTestCase {
    func testCapturedShortcutNeedsARealModifier() {
        XCTAssertNil(HotKey(keyCode: 0, flags: []))
        XCTAssertNil(HotKey(keyCode: 0, flags: [.shift]), "⇧A would block typing capitals")
        XCTAssertNotNil(HotKey(keyCode: 0, flags: [.command]), "keyCode 0 is the A key, not 'no key'")
        XCTAssertNotNil(HotKey(keyCode: 0, flags: [.control, .option]))
        XCTAssertNotNil(HotKey(keyCode: 122, flags: []), "F1 alone is fine")
    }

    func testDisplayUsesMacOSModifierOrder() {
        let key = HotKey(keyCode: 18, modifiers: [.maskCommand, .maskShift, .maskControl, .maskAlternate])
        XCTAssertEqual(key.displayString, "⌃⌥⇧⌘1")
        XCTAssertEqual(HotKey(keyCode: 49, modifiers: [.maskAlternate]).displayString, "⌥Space")
        XCTAssertEqual(HotKey(keyCode: 122, modifiers: []).displayString, "F1")
    }

    func testEqualityIgnoresModifierOrder() {
        XCTAssertEqual(
            HotKey(keyCode: 1, modifiers: [.maskCommand, .maskShift]),
            HotKey(keyCode: 1, modifiers: [.maskShift, .maskCommand])
        )
        XCTAssertNotEqual(HotKey(keyCode: 1, modifiers: [.maskCommand]), HotKey(keyCode: 2, modifiers: [.maskCommand]))
    }

    func testStoredFormatStillDecodes() throws {
        let stored = #"{"keyCode":18,"modifiers":[1048576]}"#
        let key = try JSONDecoder().decode(HotKey.self, from: Data(stored.utf8))
        XCTAssertEqual(key, HotKey(keyCode: 18, modifiers: [.maskCommand]))
        let reencoded = try JSONDecoder().decode(HotKey.self, from: JSONEncoder().encode(key))
        XCTAssertEqual(reencoded, key)
    }
}
