import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DefaultLayoutsView: View {
    @ObservedObject var smartLayoutManager: SmartLayoutManager
    @ObservedObject var keyboardLayoutManager: KeyboardLayoutManager

    var body: some View {
        List {
            Section {
                if smartLayoutManager.defaultRules.isEmpty {
                    Text("No default rules yet. Add an application to pin a layout.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(smartLayoutManager.defaultRules) { rule in
                        RuleRowView(
                            rule: rule,
                            smartLayoutManager: smartLayoutManager,
                            keyboardLayoutManager: keyboardLayoutManager
                        ) {
                            smartLayoutManager.removeRule(for: rule.appBundleID)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Default Rules")
                    Spacer()
                    Button("Add Application…") { addAppRule() }
                }
            } footer: {
                Text("These rules are always applied. They have the highest priority.")
            }

            Section {
                if smartLayoutManager.publishedRememberedLayouts.isEmpty {
                    Text("No layouts remembered yet. Work in different apps to see them here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(smartLayoutManager.publishedRememberedLayouts) { remembered in
                        RememberedLayoutRowView(remembered: remembered) {
                            smartLayoutManager.promoteToRule(remembered: remembered)
                        }
                    }
                }
            } header: {
                Text("Remembered Layouts")
            } footer: {
                Text("These layouts were automatically saved. Pin a remembered layout to turn it into a default rule.")
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addAppRule() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]

        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  let appName = bundle.localizedInfoDictionary?["CFBundleName"] as? String ?? bundle.infoDictionary?["CFBundleName"] as? String,
                  let defaultLayout = keyboardLayoutManager.availableLayouts.first else {
                let alert = NSAlert()
                alert.messageText = "Could Not Add Application"
                alert.informativeText = "Could not read application information or no keyboard layouts are available."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }

            let newRule = AppLayoutRule(appBundleID: bundleID, appName: appName, layoutID: defaultLayout.id)
            smartLayoutManager.defaultRules.append(newRule)
        }
    }
}

struct RuleRowView: View {
    let rule: AppLayoutRule
    @ObservedObject var smartLayoutManager: SmartLayoutManager
    @ObservedObject var keyboardLayoutManager: KeyboardLayoutManager
    let onDelete: () -> Void

    @State private var selectedLayoutID: String

    init(
        rule: AppLayoutRule,
        smartLayoutManager: SmartLayoutManager,
        keyboardLayoutManager: KeyboardLayoutManager,
        onDelete: @escaping () -> Void
    ) {
        self.rule = rule
        self.smartLayoutManager = smartLayoutManager
        self.keyboardLayoutManager = keyboardLayoutManager
        self.onDelete = onDelete
        self._selectedLayoutID = State(initialValue: rule.layoutID)
    }

    var body: some View {
        HStack {
            Image(nsImage: rule.appIcon)
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading) {
                Text(rule.appName).fontWeight(.semibold)
                Text(rule.appBundleID).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Picker("Layout", selection: $selectedLayoutID) {
                ForEach(keyboardLayoutManager.availableLayouts) { layout in
                    Text(layout.localizedName).tag(layout.id)
                }
            }
            .labelsHidden()
            .frame(width: 160)
            .onChange(of: selectedLayoutID) { _, newValue in
                if let index = smartLayoutManager.defaultRules.firstIndex(where: { $0.id == rule.id }) {
                    var updatedRule = smartLayoutManager.defaultRules[index]
                    updatedRule.layoutID = newValue
                    smartLayoutManager.defaultRules[index] = updatedRule
                }
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

struct RememberedLayoutRowView: View {
    let remembered: RememberedLayout
    let onPin: () -> Void

    var body: some View {
        HStack {
            Image(nsImage: remembered.appIcon)
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading) {
                Text(remembered.appName)
                    .fontWeight(.semibold)
                Text(remembered.appBundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(remembered.layoutName)
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button(action: onPin) {
                Image(systemName: "pin.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Pin this layout as a default rule")
        }
        .padding(.vertical, 4)
    }
}
