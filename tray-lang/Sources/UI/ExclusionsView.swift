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
                Text("QBlocker Exclusions")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("✕") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                Text("Applications in this list will not be protected by QBlocker. Cmd+Q will work normally for these apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if exclusionManager.excludedApps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "app.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No excluded apps")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add applications to exclude them from QBlocker protection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Excluded Applications:")
                                .font(.headline)
                            Spacer()
                            Button("Add Apps") {
                                addApps()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)
                        
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(exclusionManager.excludedApps) { app in
                                    HStack {
                                        Image(systemName: "app.fill")
                                            .foregroundColor(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text(app.bundleID)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("Remove") {
                                            exclusionManager.removeExcludedApp(app)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
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