//
//  HotKeyEditorView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

struct HotKeyEditorView: View {
    @ObservedObject var coordinator: AppCoordinator
    let hotKeyType: String
    @State private var isCapturing = false
    @State private var capturedKeyCode: Int?
    @State private var capturedModifiersArray: [CGEventFlags] = []

    private var title: String {
        hotKeyType == "spell" ? "Spell Check Hotkey" : "Main Hotkey"
    }

    private var currentHotKey: HotKey {
        hotKeyType == "spell" ? coordinator.spellCheckHotKey : coordinator.layoutHotKey
    }

    private var selectedHotKey: HotKey? {
        guard let keyCode = capturedKeyCode, !capturedModifiersArray.isEmpty else { return nil }
        return HotKey(keyCode: keyCode, modifiers: capturedModifiersArray)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedHotKey == nil ? "Current Combination" : "Selected Combination")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text((selectedHotKey ?? currentHotKey).displayString)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.medium)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            (selectedHotKey == nil ? Color.secondary : Color.green)
                                .opacity(0.12)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.vertical, 4)
            } header: {
                Text(title)
            } footer: {
                Text(
                    hotKeyType == "spell"
                        ? "Used to fix spelling in the selected text."
                        : "Used to convert the selected text between layouts."
                )
            }

            Section {
                Button(isCapturing ? "Stop Capture" : "Start Capture") {
                    if isCapturing {
                        stopCapturing()
                    } else {
                        startCapturing()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if isCapturing {
                    Text("Press any key combination…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Save Hotkey") {
                    guard let keyCode = capturedKeyCode, !capturedModifiersArray.isEmpty else { return }
                    let newHotKey = HotKey(keyCode: keyCode, modifiers: capturedModifiersArray)
                    if hotKeyType == "spell" {
                        coordinator.spellCheckHotKey = newHotKey
                    } else {
                        coordinator.layoutHotKey = newHotKey
                    }
                    coordinator.saveHotKeys()
                    capturedKeyCode = nil
                    capturedModifiersArray = []
                }
                .buttonStyle(.borderedProminent)
                .disabled(capturedKeyCode == nil || capturedModifiersArray.isEmpty)
            } header: {
                Text("Capture")
            } footer: {
                Text("Capture a new combination, then save it. Leaving this page cancels an unfinished capture.")
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .keyCaptured)) { notification in
            guard isCapturing,
                  let keyCode = notification.userInfo?["keyCode"] as? Int,
                  let modifiers = notification.userInfo?["modifiers"] as? [CGEventFlags],
                  keyCode > 0 else { return }

            capturedKeyCode = keyCode
            capturedModifiersArray = modifiers
            stopCapturing()
        }
        .onDisappear {
            stopCapturing()
        }
        .background(KeyCaptureView(isCapturing: $isCapturing))
    }

    private func startCapturing() {
        coordinator.stopKeyCapture()
        isCapturing = true
        capturedKeyCode = nil
        capturedModifiersArray = []
    }

    private func stopCapturing() {
        isCapturing = false
        coordinator.startKeyCapture()
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let keyCaptured = Notification.Name("keyCaptured")
}

struct KeyCaptureView: NSViewRepresentable {
    @Binding var isCapturing: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.cleanup()

        if isCapturing {
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags

                guard keyCode > 0 else { return event }

                var modifiers: [CGEventFlags] = []
                if flags.contains(.command) { modifiers.append(.maskCommand) }
                if flags.contains(.shift) { modifiers.append(.maskShift) }
                if flags.contains(.option) { modifiers.append(.maskAlternate) }
                if flags.contains(.control) { modifiers.append(.maskControl) }

                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .keyCaptured,
                        object: nil,
                        userInfo: [
                            "keyCode": keyCode,
                            "modifiers": modifiers
                        ]
                    )
                }

                return nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var monitor: Any?

        func cleanup() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            cleanup()
        }
    }
}
