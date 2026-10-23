import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            if !coordinator.isAccessibilityGranted {
                Section {
                    LabeledContent {
                        Button("Grant Access…") {
                            Task { await coordinator.accessibilityManager.requestPermissions(openSettings: true) }
                        }
                    } label: {
                        Label("Accessibility access is required", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Needed to read and replace selected text, fix words while typing and block ⌘Q / ⌘W.")
                    }
                }
            }

            if coordinator.isSecureInputActive {
                Section {
                    LabeledContent {
                        Button("Check Again") { coordinator.recheckSecureInput() }
                    } label: {
                        Label("Secure Input is on", systemImage: "lock.shield")
                            .foregroundStyle(.yellow)
                        Text(coordinator.secureInputStatusMessage)
                    }
                }
            }

            Section("Selected Text") {
                Toggle(isOn: $coordinator.isTextConversionEnabled) {
                    Text("Convert keyboard layout")
                    Text("Fixes text typed in the wrong layout, e.g. ghbdtn → привет.")
                }
                LabeledContent("Shortcut") {
                    HotKeyRecorder(hotKey: $coordinator.layoutHotKey, onRecordingChange: recordingChanged)
                }
                .disabled(!coordinator.isTextConversionEnabled)

                Toggle(isOn: $coordinator.isSpellCheckEnabled) {
                    Text("Fix spelling")
                    Text("Replaces misspelled words with the macOS spell checker's correction.")
                }
                .disabled(!coordinator.isTextConversionEnabled)
                LabeledContent("Shortcut") {
                    HotKeyRecorder(hotKey: $coordinator.spellCheckHotKey, onRecordingChange: recordingChanged)
                }
                .disabled(!coordinator.isTextConversionEnabled || !coordinator.isSpellCheckEnabled)
            }

            Section {
                Toggle(isOn: $coordinator.isAutoConvertEnabled) {
                    Text("Fix words while typing")
                    Text("When you press Space after a word that only makes sense in the other layout, it is retyped and the layout switches. Press Delete right away to undo.")
                }
                Toggle("Play a sound", isOn: $coordinator.isAutoConvertSoundEnabled)
                    .disabled(!coordinator.isAutoConvertEnabled)
                Toggle("Skip terminals and code editors", isOn: $coordinator.isAutoConvertSkippingCodeApps)
                    .disabled(!coordinator.isAutoConvertEnabled)
            } header: {
                Text("While Typing")
            } footer: {
                Text("Checks only the word you just finished, against the macOS dictionaries. Nothing is stored or sent anywhere.")
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $coordinator.isAutoLaunchEnabled)
                if let error = coordinator.autoLaunchError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if coordinator.isAccessibilityGranted {
                Section {
                    LabeledContent("Accessibility") {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func recordingChanged(_ isRecording: Bool) {
        isRecording ? coordinator.stopKeyCapture() : coordinator.startKeyCapture()
    }
}
