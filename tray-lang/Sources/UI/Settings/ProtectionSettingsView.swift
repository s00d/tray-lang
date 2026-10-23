import SwiftUI

struct ProtectionSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var exclusionManager: ExclusionManager
    @ObservedObject var blocker: HotkeyBlockerManager

    private var isAnyEnabled: Bool {
        coordinator.isCmdQBlockerEnabled || coordinator.isCmdWBlockerEnabled
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $coordinator.isCmdQBlockerEnabled) {
                    Text("Hold ⌘Q to quit")
                    Text("A quick press shows a reminder instead of quitting the app.")
                }
                Toggle(isOn: $coordinator.isCmdWBlockerEnabled) {
                    Text("Hold ⌘W to close windows")
                    Text("A quick press shows a reminder instead of closing the window.")
                }
                Picker("Hold for", selection: $coordinator.blockerDelay) {
                    ForEach(1...5, id: \.self) { seconds in
                        Text(seconds == 1 ? "1 second" : "\(seconds) seconds").tag(seconds)
                    }
                }
                .disabled(!isAnyEnabled)
            }

            Section {
                LabeledContent("Accidental quits", value: "\(blocker.accidentalQuits)")
                LabeledContent("Accidental window closes", value: "\(blocker.accidentalCloses)")
            } header: {
                HStack {
                    Text("Prevented")
                    Spacer()
                    Button("Reset") { blocker.resetStatistics() }
                        .controlSize(.small)
                        .disabled(blocker.accidentalQuits == 0 && blocker.accidentalCloses == 0)
                }
            }

            Section {
                if exclusionManager.excludedApps.isEmpty {
                    Text("No excluded apps.")
                        .foregroundStyle(.secondary)
                }
                ForEach(exclusionManager.excludedApps) { app in
                    AppRow(name: app.name, bundleID: app.bundleID) {
                        Button {
                            exclusionManager.removeExcludedApp(app)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
            } header: {
                HStack {
                    Text("Excluded Apps")
                    Spacer()
                    AddAppMenu(excluding: Set(exclusionManager.excludedApps.map(\.bundleID)), allowsMultiple: true) { apps in
                        for app in apps {
                            exclusionManager.addExcludedApp(ExcludedApp(name: app.name, bundleID: app.bundleID, path: app.path))
                        }
                    }
                }
            } footer: {
                Text("⌘Q and ⌘W work normally in these apps.")
            }
        }
        .formStyle(.grouped)
    }
}
