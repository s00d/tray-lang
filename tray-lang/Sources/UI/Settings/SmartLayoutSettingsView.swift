import SwiftUI

struct SmartLayoutSettingsView: View {
    @ObservedObject var smartLayoutManager: SmartLayoutManager
    @ObservedObject var keyboardLayoutManager: KeyboardLayoutManager
    @State private var showsRemembered = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $smartLayoutManager.isEnabled) {
                    Text("Switch layout per app")
                    Text("Each app gets back the layout you last used in it, unless a rule below says otherwise.")
                }
            }

            Section {
                if smartLayoutManager.defaultRules.isEmpty {
                    Text("No rules. Add an app to always open it in a chosen layout.")
                        .foregroundStyle(.secondary)
                }
                ForEach($smartLayoutManager.defaultRules) { $rule in
                    AppRow(name: rule.appName, bundleID: rule.appBundleID) {
                        Picker("Layout", selection: $rule.layoutID) {
                            ForEach(keyboardLayoutManager.availableLayouts) { layout in
                                Text(layout.localizedName).tag(layout.id)
                            }
                            if !keyboardLayoutManager.availableLayouts.contains(where: { $0.id == rule.layoutID }) {
                                Text("Unavailable layout").tag(rule.layoutID)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button {
                            smartLayoutManager.removeRule(for: rule.appBundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove rule")
                    }
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    AddAppMenu(
                        excluding: Set(smartLayoutManager.defaultRules.map(\.appBundleID)),
                        allowsMultiple: false,
                        onPick: addRules
                    )
                    .disabled(keyboardLayoutManager.availableLayouts.isEmpty)
                }
            } footer: {
                Text("Rules always win over remembered layouts.")
            }

            Section {
                let remembered = smartLayoutManager.publishedRememberedLayouts
                let uninstalled = remembered.filter { !$0.isInstalled }.count
                LabeledContent("Apps with a remembered layout", value: "\(remembered.count)")
                HStack {
                    Button("Show All…") { showsRemembered = true }
                        .disabled(remembered.isEmpty)
                    if uninstalled > 0 {
                        Button("Forget \(uninstalled) Uninstalled") { smartLayoutManager.forgetUninstalledApps() }
                    }
                }
            } header: {
                Text("Remembered")
            } footer: {
                Text("Updated whenever you leave an app. Make a rule from any of them to fix its layout.")
            }
            .disabled(!smartLayoutManager.isEnabled)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsRemembered) {
            RememberedLayoutsSheet(smartLayoutManager: smartLayoutManager)
        }
    }

    /// New rules start with the layout the app was last used with, else the current one.
    private func addRules(_ apps: [AppPicker.PickedApp]) {
        for app in apps {
            let remembered = smartLayoutManager.publishedRememberedLayouts.first { $0.appBundleID == app.bundleID }?.layoutID
            guard let layoutID = remembered ?? keyboardLayoutManager.currentLayoutID ?? keyboardLayoutManager.availableLayouts.first?.id else { return }
            smartLayoutManager.setRule(bundleID: app.bundleID, appName: app.name, layoutID: layoutID)
        }
    }
}

/// All remembered apps; a lazy List, so hundreds of rows cost only what is on screen.
private struct RememberedLayoutsSheet: View {
    @ObservedObject var smartLayoutManager: SmartLayoutManager
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [RememberedLayout] {
        let all = smartLayoutManager.publishedRememberedLayouts
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.appName.localizedCaseInsensitiveContains(query)
                || $0.appBundleID.localizedCaseInsensitiveContains(query)
                || $0.layoutName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(rows) { remembered in
                AppRow(name: remembered.appName, bundleID: remembered.appBundleID) {
                    if !remembered.isInstalled {
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(remembered.layoutName)
                        .foregroundStyle(.secondary)
                    Button("Make Rule") { smartLayoutManager.promoteToRule(remembered: remembered) }
                        .controlSize(.small)
                    Button {
                        smartLayoutManager.forget(bundleID: remembered.appBundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Forget")
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search apps or layouts")
            Divider()
            HStack {
                Text("\(rows.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 520)
    }
}
