//
//  ExclusionsView.swift
//  tray-lang
//

import SwiftUI

struct ExclusionsView: View {
    @ObservedObject var exclusionManager: ExclusionManager

    var body: some View {
        List {
            Section {
                if exclusionManager.excludedApps.isEmpty {
                    ContentUnavailableView(
                        "No applications excluded",
                        systemImage: "shield.slash",
                        description: Text("Add apps where Cmd+Q / Cmd+W protection should stay off.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(exclusionManager.excludedApps) { app in
                        ExclusionRowView(app: app) {
                            exclusionManager.removeExcludedApp(app)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Excluded Applications")
                    Spacer()
                    Button("Add Application…") {
                        addApps()
                    }
                }
            } footer: {
                Text("Cmd+Q and Cmd+W protection will be disabled for apps in this list.")
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addApps() {
        let selectedApps = exclusionManager.selectApps()
        for app in selectedApps {
            exclusionManager.addExcludedApp(app)
        }
    }
}

#Preview {
    ExclusionsView(exclusionManager: ExclusionManager())
}
