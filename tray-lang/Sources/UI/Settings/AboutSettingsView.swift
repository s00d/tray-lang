import SwiftUI
import AppKit

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App icon and name
                VStack(spacing: 16) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)
                    
                    Text("Tray Lang")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Description
                VStack(spacing: 12) {
                    Text("Automatic keyboard layout switcher for selected text")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("Tray Lang helps you quickly switch keyboard layouts for selected text. Simply select text in any application, press your configured hotkey, and the text will be transformed to the opposite layout while switching the system keyboard layout.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Features
                VStack(alignment: .leading, spacing: 8) {
                    Text("Features:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        FeatureRow(icon: "keyboard", text: "Customizable hotkeys")
                        FeatureRow(icon: "textformat.abc", text: "Customizable character mappings")
                        FeatureRow(icon: "menubar.rectangle", text: "Tray icon for easy access")
                        FeatureRow(icon: "gear", text: "Auto-launch at system startup")
                        FeatureRow(icon: "lock.shield", text: "Accessibility permissions for text manipulation")
                    }
                }
                .padding(.horizontal)
                
                // Developer info
                VStack(spacing: 8) {
                    Text("Developed by s00d")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("GitHub Repository") {
                        if let url = URL(string: "https://github.com/s00d/tray-lang") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
                    
                    Text("© 2025 All rights reserved")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
        }
    }
}

