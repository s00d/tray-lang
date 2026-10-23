import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case conversion
    case smartLayout
    case protection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .conversion: "Conversion"
        case .smartLayout: "Smart Layout"
        case .protection: "Quit Protection"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .conversion: "character.bubble"
        case .smartLayout: "keyboard.badge.ellipsis"
        case .protection: "hand.raised"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsView(coordinator: coordinator)
        case .conversion:
            ConversionSettingsView(transformer: coordinator.textTransformer)
        case .smartLayout:
            SmartLayoutSettingsView(
                smartLayoutManager: coordinator.smartLayoutManager,
                keyboardLayoutManager: coordinator.keyboardLayoutManager
            )
        case .protection:
            ProtectionSettingsView(
                coordinator: coordinator,
                exclusionManager: coordinator.exclusionManager,
                blocker: coordinator.hotkeyBlockerManager
            )
        }
    }
}

/// App row used by the rule and exclusion lists.
struct AppRow<Trailing: View>: View {
    let name: String
    let bundleID: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.shared.icon(for: bundleID))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

/// "Add App" menu: running apps first (one click), then a file chooser.
struct AddAppMenu: View {
    var title = "Add App"
    var excluding: Set<String> = []
    let allowsMultiple: Bool
    let onPick: ([AppPicker.PickedApp]) -> Void

    var body: some View {
        Menu(title) {
            let running = AppPicker.runningApps().filter { !excluding.contains($0.bundleID) }
            if !running.isEmpty {
                Section("Running") {
                    ForEach(running, id: \.bundleID) { app in
                        Button {
                            onPick([app])
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: IconCache.shared.icon(for: app.bundleID))
                            }
                        }
                    }
                }
                Divider()
            }
            Button("Choose from Applications…") {
                AppPicker.chooseApplications(allowsMultiple: allowsMultiple, completion: onPick)
            }
        }
        .fixedSize()
        .controlSize(.small)
    }
}

enum AppPicker {
    struct PickedApp {
        let name: String
        let bundleID: String
        let path: String
    }

    /// Regular (Dock) apps that are running now, except this one, by name.
    static func runningApps() -> [PickedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> PickedApp? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return PickedApp(name: app.localizedName ?? bundleID, bundleID: bundleID, path: app.bundleURL?.path ?? "")
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Non-modal open panel for choosing applications.
    static func chooseApplications(allowsMultiple: Bool, completion: @escaping ([PickedApp]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = allowsMultiple ? "Choose Applications" : "Choose an Application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = allowsMultiple
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK else { return completion([]) }
            let apps = panel.urls.compactMap { url -> PickedApp? in
                guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
                return PickedApp(name: FileManager.default.displayName(atPath: url.path), bundleID: bundleID, path: url.path)
            }
            completion(apps)
        }
    }
}
