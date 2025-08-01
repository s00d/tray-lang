//
//  HotKeyEditorView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

struct HotKeyEditorView: View {
    @ObservedObject var trayLangManager: TrayLangManager
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    @State private var capturedKey: String = ""
    @State private var capturedModifiers: String = ""
    @State private var capturedKeyCode: Int?
    @State private var capturedModifiersArray: [CGEventFlags] = []
    
    var availableKeyCodes: [KeyInfo] {
        return TrayLangManager.getAvailableKeyCodes()
    }
    
    var availableModifiers: [(CGEventFlags, String)] {
        return TrayLangManager.getAvailableModifiers()
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Hotkey Editor")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("✕") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Always show selected combination
            Group {
                if let keyCode = capturedKeyCode, !capturedModifiersArray.isEmpty {
                    // Show captured combination
                    let hotKey = HotKey(keyCode: keyCode, modifiers: capturedModifiersArray)
                    Text("Selected: " + hotKey.description)
                        .font(.title3)
                        .fontWeight(.medium)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text("Current combination: " + trayLangManager.hotKey.description)
                        .font(.title3)
                        .fontWeight(.medium)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            // Capture button
            Button(isCapturing ? "Stop capture" : "Start capture") {
                if isCapturing {
                    stopCapturing()
                } else {
                    startCapturing()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            // One confirmation button
            Button("Confirm") {
                if let keyCode = capturedKeyCode, !capturedModifiersArray.isEmpty {
                    trayLangManager.hotKey = HotKey(keyCode: keyCode, modifiers: capturedModifiersArray)
                    trayLangManager.saveHotKey()
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(capturedKeyCode == nil || capturedModifiersArray.isEmpty)

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .padding(.bottom)
        }
        .padding()
        .frame(width: 400, height: 300)
        .onReceive(NotificationCenter.default.publisher(for: .keyCaptured)) { notification in
            print("📨 Получено уведомление о захвате клавиши")
            print("🔍 isCapturing: \(isCapturing)")
            
            if isCapturing {
                print("📋 userInfo: \(notification.userInfo ?? [:])")
                
                if let keyCode = notification.userInfo?["keyCode"] as? Int,
                   let modifiers = notification.userInfo?["modifiers"] as? [CGEventFlags],
                   keyCode > 0 { // Игнорируем события с keyCode = 0
                    print("✅ Успешно извлечены данные: keyCode=\(keyCode), modifiers=\(modifiers)")
                    capturedKeyCode = keyCode
                    capturedModifiersArray = modifiers
                    stopCapturing()
                } else {
                    print("❌ Не удалось извлечь данные из уведомления или keyCode = 0")
                    print("📋 Типы данных: keyCode=\(type(of: notification.userInfo?["keyCode"])), modifiers=\(type(of: notification.userInfo?["modifiers"]))")
                }
            } else {
                print("⚠️ Захват не активен, игнорируем уведомление")
            }
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
        print("🎯 Начинаем захват клавиш...")
        isCapturing = true
        capturedKeyCode = nil
        capturedModifiersArray = []
        print("✅ Локальный захват клавиш запущен успешно")
    }
    
    private func stopCapturing() {
        isCapturing = false
        trayLangManager.stopKeyCapture()
    }
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
                
                print("🔍 Локальный захват: Клавиша \(keyCode), Флаги \(flags.rawValue)")
                
                // Проверяем, что keyCode валидный
                guard keyCode > 0 else {
                    print("⚠️ Игнорируем событие с keyCode = 0")
                    return event
                }
                
                // Собираем все активные модификаторы
                var modifiers: [CGEventFlags] = []
                if flags.contains(.command) {
                    modifiers.append(.maskCommand)
                    print("  - Command")
                }
                if flags.contains(.shift) {
                    modifiers.append(.maskShift)
                    print("  - Shift")
                }
                if flags.contains(.option) {
                    modifiers.append(.maskAlternate)
                    print("  - Option")
                }
                if flags.contains(.control) {
                    modifiers.append(.maskControl)
                    print("  - Control")
                }
                
                print("📋 Собранные модификаторы: \(modifiers.map { $0.rawValue })")
                
                // Отправляем уведомление с захваченными данными
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .keyCaptured,
                        object: nil,
                        userInfo: [
                            "keyCode": keyCode,
                            "modifiers": modifiers
                        ]
                    )
                    print("📤 Отправлено уведомление о захвате клавиши: \(keyCode)")
                }
                
                return nil // Поглощаем событие
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