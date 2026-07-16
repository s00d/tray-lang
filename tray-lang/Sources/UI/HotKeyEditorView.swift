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
    let onDone: () -> Void
    @State private var isCapturing = false
    @State private var capturedKey: String = ""
    @State private var capturedModifiers: String = ""
    @State private var capturedKeyCode: Int?
    @State private var capturedModifiersArray: [CGEventFlags] = []
    
    var availableKeyCodes: [KeyInfo] {
        return KeyUtils.getAvailableKeyCodes()
    }
    
    var availableModifiers: [(CGEventFlags, String)] {
        return KeyUtils.getAvailableModifiers()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hotkey Editor")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("✕") { onDone() }
                    .buttonStyle(.plain)
            }
            .padding()
            Divider()
            
            VStack(spacing: 20) {
                // Current/Selected combination display
                Group {
                    if let keyCode = capturedKeyCode, !capturedModifiersArray.isEmpty {
                        // Show captured combination
                        let hotKey = HotKey(keyCode: keyCode, modifiers: capturedModifiersArray)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Combination")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(hotKey.displayString)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.medium)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Combination")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text((hotKeyType == "spell" ? coordinator.spellCheckHotKey : coordinator.layoutHotKey).displayString)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.medium)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Capture section
                VStack(spacing: 12) {
                    Text("Capture New Hotkey")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
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
                        Text("Press any key combination...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.vertical)
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    onDone()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Confirm") {
                    if let keyCode = capturedKeyCode, !capturedModifiersArray.isEmpty {
                        let newHotKey = HotKey(keyCode: keyCode, modifiers: capturedModifiersArray)
                        if hotKeyType == "spell" {
                            coordinator.spellCheckHotKey = newHotKey
                        } else {
                            coordinator.layoutHotKey = newHotKey
                        }
                        coordinator.saveHotKeys()
                    }
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .disabled(capturedKeyCode == nil || capturedModifiersArray.isEmpty)
            }
            .padding()
        }
        .frame(width: 350, height: 300)
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
        .background(
            // Локальный захват клавиш через NSEvent
            KeyCaptureView(isCapturing: $isCapturing)
        )
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

// Вспомогательное представление для захвата клавиш
struct KeyCaptureView: NSViewRepresentable {
    @Binding var isCapturing: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Очищаем предыдущий монитор
        context.coordinator.cleanup()
        
        if isCapturing {
            // Добавляем локальный монитор событий
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
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
        
        deinit {
            cleanup()
        }
    }
} 