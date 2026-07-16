import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    private var isProtectionSettingsVisible: Bool {
        coordinator.isCmdQBlockerEnabled || coordinator.isCmdWBlockerEnabled
    }
    
    var body: some View {
        List {
            Section("Permissions & Status") {
                SettingsRow(
                    icon: "lock.shield",
                    iconColor: coordinator.isAccessibilityGranted ? .green : .red,
                    title: "Accessibility",
                    subtitle: coordinator.isAccessibilityGranted ? "Granted" : "Required"
                ) {
                    Button(coordinator.isAccessibilityGranted ? "Granted" : "Grant...") {
                        Task {
                            await coordinator.accessibilityManager.requestPermissions()
                        }
                    }
                    .disabled(coordinator.isAccessibilityGranted)
                }
                
                if coordinator.isSecureInputActive {
                    SettingsRow(
                        icon: "exclamationmark.shield",
                        iconColor: .yellow,
                        title: "Secure Input Active",
                        subtitle: coordinator.secureInputStatusMessage
                    ) {
                        Button("Recheck") {
                            coordinator.recheckSecureInput()
                        }
                    }
                }
                
                HStack(spacing: 16) {
                    StatusIndicator(
                        isActive: coordinator.isTextConversionEnabled && coordinator.isAccessibilityGranted,
                        icon: "keyboard",
                        color: .green,
                        tooltip: "Hotkey Active"
                    )
                    
                    StatusIndicator(
                        isActive: isProtectionSettingsVisible && coordinator.isAccessibilityGranted,
                        icon: "shield",
                        color: .orange,
                        tooltip: "Protection Active"
                    )
                    
                    StatusIndicator(
                        isActive: coordinator.isSmartLayoutEnabled,
                        icon: "brain.head.profile",
                        color: .cyan,
                        tooltip: "Smart Layout Enabled"
                    )
                }
                .padding(.vertical, 8)
            }
            
            Section("Main Hotkey") {
                SettingsRow(icon: "keyboard", iconColor: .blue, title: "Hotkey", subtitle: "For converting selected text") {
                    Button(coordinator.layoutHotKeyDisplay) {
                        NotificationCenter.default.post(name: .openHotKeyEditor, object: "layout")
                    }
                }
            }
            
            Section("Spell Check") {
                SettingsRow(icon: "text.badge.checkmark", iconColor: .green, title: "Fix Spelling", subtitle: "Enable spell check feature") {
                    Toggle("", isOn: $coordinator.isSpellCheckEnabled)
                }
                
                SettingsRow(icon: "keyboard", iconColor: .blue, title: "Spell Check Hotkey", subtitle: "For fixing selected text") {
                    Button(coordinator.spellCheckHotKeyDisplay) {
                        NotificationCenter.default.post(name: .openHotKeyEditor, object: "spell")
                    }
                }
                .disabled(!coordinator.isSpellCheckEnabled)
            }
            
            Section("Behavior") {
                SettingsRow(icon: "arrow.up.circle", iconColor: .purple, title: "Auto Launch", subtitle: "Launch Tray Lang on system login") {
                    Toggle("", isOn: $coordinator.isAutoLaunchEnabled)
                }
            }
            
            Section("Smart Switcher") {
                SettingsRow(icon: "brain.head.profile", iconColor: .cyan, title: "Smart Layout", subtitle: "Remember layout for each application") {
                    Toggle("", isOn: $coordinator.isSmartLayoutEnabled)
                }
                
                SettingsRow(icon: "list.bullet.rectangle.portrait", iconColor: .green, title: "Default Rules", subtitle: "Set layout for specific applications") {
                    Button("Configure...") {
                        NotificationCenter.default.post(name: .openDefaultLayoutsEditor, object: nil)
                    }
                }
                .disabled(!coordinator.isSmartLayoutEnabled)
            }
            
            Section("Conversion") {
                SettingsRow(icon: "textformat.abc", iconColor: .orange, title: "Text Conversion", subtitle: "Enable text conversion feature") {
                    Toggle("", isOn: $coordinator.isTextConversionEnabled)
                }
                
                SettingsRow(icon: "pencil", iconColor: .orange, title: "Symbols & Languages", subtitle: "Edit symbol replacement rules") {
                    Button("Edit...") {
                        NotificationCenter.default.post(name: .openSymbolsEditor, object: nil)
                    }
                }
            }
            
            Section("Accidental Press Protection") {
                SettingsRow(icon: "q.circle", iconColor: .red, title: "Block Cmd+Q", subtitle: "Prevent accidental app quits") {
                    Toggle("", isOn: $coordinator.isCmdQBlockerEnabled)
                }
                
                SettingsRow(icon: "w.circle", iconColor: .orange, title: "Block Cmd+W", subtitle: "Prevent accidental window closes") {
                    Toggle("", isOn: $coordinator.isCmdWBlockerEnabled)
                }
            }
            
            Section("Protection Settings") {
                SettingsRow(icon: "timer", iconColor: .gray, title: "Hold Delay", subtitle: "Time to hold keys before triggering") {
                    Stepper("\(coordinator.blockerDelay) sec", value: $coordinator.blockerDelay, in: 1...5)
                }
                .disabled(!isProtectionSettingsVisible)
                
                SettingsRow(icon: "shield.slash", iconColor: .indigo, title: "Exclusions", subtitle: "Apps where protection won't work") {
                    Button("Configure...") {
                        NotificationCenter.default.post(name: .openExclusionsView, object: nil)
                    }
                }
                .disabled(!isProtectionSettingsVisible)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
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
