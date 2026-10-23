import Foundation
import AppKit

struct RememberedLayout: Identifiable, Hashable {
    var id: String { appBundleID }
    var appBundleID: String
    var appName: String
    var layoutID: String
    var layoutName: String
    var isInstalled = true

    var appIcon: NSImage {
        IconCache.shared.icon(for: appBundleID)
    }
}

/// Gives each app back its keyboard layout: a fixed rule if there is one, else the layout it was last left in.
final class SmartLayoutManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            AppDefaults.store.set(isEnabled, forKey: DefaultsKeys.smartLayoutEnabled)
            isEnabled ? startMonitoring() : stopMonitoring()
        }
    }

    @Published var defaultRules: [AppLayoutRule] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(defaultRules) {
                AppDefaults.store.set(data, forKey: DefaultsKeys.smartLayoutRules)
            }
            updatePublishedRememberedLayouts()
        }
    }

    @Published private(set) var publishedRememberedLayouts: [RememberedLayout] = []

    private let keyboardLayoutManager: KeyboardLayoutManager
    private var rememberedLayouts: [String: String] = [:]
    /// bundle ID → display name; filled from activation notifications, LaunchServices only as a fallback.
    private var appNames: [String: String] = [:]
    /// bundle ID → whether the app is still installed; asked once per app.
    private var installed: [String: Bool] = [:]
    private var observers: [NSObjectProtocol] = []
    private var saveTask: DispatchWorkItem?

    init(keyboardLayoutManager: KeyboardLayoutManager) {
        self.keyboardLayoutManager = keyboardLayoutManager
        isEnabled = AppDefaults.store.bool(forKey: DefaultsKeys.smartLayoutEnabled)
        if let data = AppDefaults.store.data(forKey: DefaultsKeys.smartLayoutRules),
           let rules = try? JSONDecoder().decode([AppLayoutRule].self, from: data) {
            defaultRules = rules
        }
        rememberedLayouts = AppDefaults.store.dictionary(forKey: DefaultsKeys.rememberedAppLayouts) as? [String: String] ?? [:]
        updatePublishedRememberedLayouts()
        if isEnabled {
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
        saveTask?.perform()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                self?.appDeactivated(note)
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                self?.appActivated(note)
            },
        ]
    }

    private func stopMonitoring() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }

    private static func app(in note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private func appDeactivated(_ note: Notification) {
        guard let app = Self.app(in: note),
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !defaultRules.contains(where: { $0.appBundleID == bundleID }),
              let layoutID = keyboardLayoutManager.currentLayoutID,
              rememberedLayouts[bundleID] != layoutID else { return }
        if let name = app.localizedName {
            appNames[bundleID] = name
        }
        rememberedLayouts[bundleID] = layoutID
        scheduleSave()
        updatePublishedRememberedLayouts()
    }

    private func appActivated(_ note: Notification) {
        guard let bundleID = Self.app(in: note)?.bundleIdentifier else { return }
        let target = defaultRules.first(where: { $0.appBundleID == bundleID })?.layoutID ?? rememberedLayouts[bundleID]
        if let target, target != keyboardLayoutManager.currentLayoutID {
            keyboardLayoutManager.switchToLayout(id: target)
        }
    }

    // MARK: - Rules

    func addRule(for app: NSRunningApplication, layoutID: String) {
        guard let bundleID = app.bundleIdentifier, let appName = app.localizedName else { return }
        setRule(bundleID: bundleID, appName: appName, layoutID: layoutID)
    }

    /// One rule per app; replaces an existing one in a single assignment (one save, one UI update).
    func setRule(bundleID: String, appName: String, layoutID: String) {
        defaultRules = defaultRules.filter { $0.appBundleID != bundleID }
            + [AppLayoutRule(appBundleID: bundleID, appName: appName, layoutID: layoutID)]
    }

    func removeRule(for bundleID: String) {
        defaultRules.removeAll { $0.appBundleID == bundleID }
    }

    func promoteToRule(remembered: RememberedLayout) {
        rememberedLayouts.removeValue(forKey: remembered.appBundleID)
        scheduleSave()
        setRule(bundleID: remembered.appBundleID, appName: remembered.appName, layoutID: remembered.layoutID)
    }

    /// Drops remembered layouts of apps that are no longer installed.
    func forgetUninstalledApps() {
        let missing = publishedRememberedLayouts.filter { !$0.isInstalled }.map(\.appBundleID)
        guard !missing.isEmpty else { return }
        missing.forEach { rememberedLayouts.removeValue(forKey: $0) }
        scheduleSave()
        updatePublishedRememberedLayouts()
    }

    func forget(bundleID: String) {
        rememberedLayouts.removeValue(forKey: bundleID)
        scheduleSave()
        updatePublishedRememberedLayouts()
    }

    // MARK: - Persistence

    /// Quick app switching changes the map often; write it at most every half second.
    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            AppDefaults.store.set(self.rememberedLayouts, forKey: DefaultsKeys.rememberedAppLayouts)
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func isInstalled(_ bundleID: String) -> Bool {
        if let cached = installed[bundleID] { return cached }
        let value = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        installed[bundleID] = value
        return value
    }

    private func name(for bundleID: String) -> String {
        if let cached = appNames[bundleID] { return cached }
        let name = NSWorkspace.shared.applicationName(for: bundleID)
        appNames[bundleID] = name
        return name
    }

    private func updatePublishedRememberedLayouts() {
        let ruled = Set(defaultRules.map(\.appBundleID))
        let layoutNames = Dictionary(keyboardLayoutManager.availableLayouts.map { ($0.id, $0.localizedName) }, uniquingKeysWith: { first, _ in first })
        publishedRememberedLayouts = rememberedLayouts
            .filter { !ruled.contains($0.key) }
            .map { bundleID, layoutID in
                RememberedLayout(
                    appBundleID: bundleID,
                    appName: name(for: bundleID),
                    layoutID: layoutID,
                    layoutName: layoutNames[layoutID] ?? SystemKeyboardLayouts.localizedName(ofLayoutID: layoutID) ?? layoutID,
                    isInstalled: isInstalled(bundleID)
                )
            }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
}
