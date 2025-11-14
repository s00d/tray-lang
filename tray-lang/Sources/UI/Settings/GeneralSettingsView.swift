import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    @State private var showingDefaultLayoutsEditor = false
    
    var body: some View {
        Form {
            Section(header: Text("Status")) {
                HStack(spacing: 16) {
                    StatusIndicator(
                        isActive: coordinator.hotKeyManager.isEnabled,
                        icon: "keyboard",
                        color: .green,
                        tooltip: "Hotkey Active"
                    )
                    
                    StatusIndicator(
                        isActive: coordinator.accessibilityManager.isAccessibilityGranted(),
                        icon: "lock.shield",
                        color: .blue,
                        tooltip: "Accessibility Granted"
                    )
                    
                    StatusIndicator(
                        isActive: coordinator.hotkeyBlockerManager.isCmdQEnabled || coordinator.hotkeyBlockerManager.isCmdWEnabled,
                        icon: "shield",
                        color: .orange,
                        tooltip: "Protection Active"
                    )
                    
                    StatusIndicator(
                        isActive: coordinator.smartLayoutManager.isEnabled,
                        icon: "brain.head.profile",
                        color: .cyan,
                        tooltip: "Smart Layout Enabled"
                    )
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Main Hotkey")) {
                SettingsRow(icon: "keyboard", iconColor: .blue, title: "Hotkey", subtitle: "For converting selected text") {
                    Button(coordinator.hotKeyManager.hotKey.displayString) {
                        NotificationCenter.default.post(name: .openHotKeyEditor, object: nil)
                    }
                }
            }
            
            Section(header: Text("Behavior")) {
                SettingsRow(icon: "arrow.up.circle", iconColor: .purple, title: "Auto Launch", subtitle: "Launch Tray Lang on system login") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.autoLaunchManager.isAutoLaunchEnabled() },
                        set: { newValue in
                            if newValue {
                                coordinator.autoLaunchManager.enableAutoLaunch()
                            } else {
                                coordinator.autoLaunchManager.disableAutoLaunch()
                            }
                        }
                    ))
                }
            }
            
            Section(header: Text("Smart Switcher")) {
                SettingsRow(icon: "brain.head.profile", iconColor: .cyan, title: "Smart Layout", subtitle: "Remember layout for each application") {
                    Toggle("", isOn: $coordinator.smartLayoutManager.isEnabled)
                }
                
                SettingsRow(icon: "list.bullet.rectangle.portrait", iconColor: .green, title: "Default Rules", subtitle: "Set layout for specific applications") {
                    Button("Configure...") {
                        showingDefaultLayoutsEditor = true
                    }
                }
                .disabled(!coordinator.smartLayoutManager.isEnabled)
            }
            
            Section(header: Text("Conversion")) {
                SettingsRow(icon: "textformat.abc", iconColor: .orange, title: "Text Conversion", subtitle: "Enable text conversion feature") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.hotKeyManager.isEnabled },
                        set: { newValue in
                            if newValue {
                                coordinator.hotKeyManager.startMonitoring()
                            } else {
                                coordinator.hotKeyManager.stopMonitoring()
                            }
                        }
                    ))
                }
                
                SettingsRow(icon: "pencil", iconColor: .orange, title: "Symbols & Languages", subtitle: "Edit symbol replacement rules") {
                    Button("Edit...") {
                        NotificationCenter.default.post(name: .openSymbolsEditor, object: nil)
                    }
                }
            }
            
            Section(header: Text("Accidental Press Protection")) {
                SettingsRow(icon: "q.circle", iconColor: .red, title: "Block Cmd+Q", subtitle: "Prevent accidental app quits") {
                    Toggle("", isOn: $coordinator.hotkeyBlockerManager.isCmdQEnabled)
                }
                
                SettingsRow(icon: "w.circle", iconColor: .orange, title: "Block Cmd+W", subtitle: "Prevent accidental window closes") {
                    Toggle("", isOn: $coordinator.hotkeyBlockerManager.isCmdWEnabled)
                }
            }
            
            if coordinator.hotkeyBlockerManager.isCmdQEnabled || coordinator.hotkeyBlockerManager.isCmdWEnabled {
                Section(header: Text("Protection Settings")) {
                    SettingsRow(icon: "timer", iconColor: .gray, title: "Hold Delay", subtitle: "Time to hold keys before triggering") {
                        Stepper("\(coordinator.hotkeyBlockerManager.delay) sec", value: $coordinator.hotkeyBlockerManager.delay, in: 1...5)
                            .onChange(of: coordinator.hotkeyBlockerManager.delay) { _, _ in
                                coordinator.hotkeyBlockerManager.saveSettings()
                            }
                    }
                    
                    SettingsRow(icon: "shield.slash", iconColor: .indigo, title: "Exclusions", subtitle: "Apps where protection won't work") {
                        Button("Configure...") {
                            NotificationCenter.default.post(name: .openExclusionsView, object: nil)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingDefaultLayoutsEditor) {
            DefaultLayoutsView(
                smartLayoutManager: coordinator.smartLayoutManager,
                keyboardLayoutManager: coordinator.keyboardLayoutManager
            )
        }
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let isActive: Bool
    let icon: String
    let color: Color
    let tooltip: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? color : .gray)
            
            Circle()
                .fill(isActive ? color : .gray.opacity(0.3))
                .frame(width: 8, height: 8)
        }
        .help(tooltip)
    }
}
