//
//  ExclusionsView.swift
//  tray-lang
//
//  Created by Stephen Radford on 07/05/2016.
//  Copyright © 2016 Cocoon Development Ltd. All rights reserved.
//  Adapted for tray-lang project
//

import SwiftUI

struct ExclusionsView: View {
    @ObservedObject var exclusionManager: ExclusionManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Hotkey Blocker Exclusions")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("✕") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            Divider()
            
            // Content
            List {
                Section {
                    // Проверяем, пуст ли список
                    if exclusionManager.excludedApps.isEmpty {
                        Text("No applications excluded.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding()
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
                        Button("Add Application...") {
                            addApps()
                        }
                    }
                } footer: {
                    Text("Cmd+Q and Cmd+W protection will be disabled for apps in this list.")
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            
            // Footer buttons
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 450)
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