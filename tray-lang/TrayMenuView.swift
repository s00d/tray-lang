//
//  TrayMenuView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

struct TrayMenuView: View {
    @StateObject private var trayLangManager: TrayLangManager
    let showMainWindow: () -> Void
    
    init(trayLangManager: TrayLangManager? = nil, showMainWindow: @escaping () -> Void) {
        if let manager = trayLangManager {
            self._trayLangManager = StateObject(wrappedValue: manager)
        } else {
            self._trayLangManager = StateObject(wrappedValue: TrayLangManager())
        }
        self.showMainWindow = showMainWindow
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Layout status
            HStack {
                Text("Layout: \(trayLangManager.currentLayout)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            // Main menu items (buttons with icons and text)
            VStack(spacing: 0) {
                Divider()
                Button(action: { openHotKeyEditorWindow() }) {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundColor(.blue)
                        Text("Hotkey Editor")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Button(action: { openSymbolsEditorWindow() }) {
                    HStack {
                        Image(systemName: "character.textbox")
                            .foregroundColor(.green)
                        Text("Symbols Editor")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                
                HStack {
                    Toggle("Auto Launch", isOn: Binding(
                        get: { trayLangManager.isAutoLaunchEnabled() },
                        set: { newValue in
                            if newValue {
                                trayLangManager.enableAutoLaunch()
                            } else {
                                trayLangManager.disableAutoLaunch()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                
                Button(action: { 
                    print("🔍 Settings button in tray pressed")
                    showMainWindow() 
                }) {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundColor(.orange)
                        Text("Settings")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Button(action: { showAboutWindow() }) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.purple)
                        Text("About")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                            .foregroundColor(.red)
                        Text("Quit")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 250)
    }
    
    private func openHotKeyEditorWindow() {
        // Проверяем, открыто ли главное окно
        if let mainWindow = NSApp.windows.first(where: { $0.title == "Tray Lang" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            // Если окно не открыто, сначала открываем его
            showMainWindow()
        }
        
        // Отправляем уведомление для открытия редактора горячих клавиш
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openHotKeyEditor, object: nil)
        }
    }
    
    private func openSymbolsEditorWindow() {
        // Проверяем, открыто ли главное окно
        if let mainWindow = NSApp.windows.first(where: { $0.title == "Tray Lang" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            // Если окно не открыто, сначала открываем его
            showMainWindow()
        }
        
        // Отправляем уведомление для открытия редактора символов
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openSymbolsEditor, object: nil)
        }
    }
    
    private func showAboutWindow() {
        // Проверяем, открыто ли главное окно
        if let mainWindow = NSApp.windows.first(where: { $0.title == "Tray Lang" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            // Если окно не открыто, сначала открываем его
            showMainWindow()
        }
        
        // Отправляем уведомление для показа окна About
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .showAboutWindow, object: nil)
        }
    }
}

// Расширения для уведомлений
extension Notification.Name {
    static let openHotKeyEditor = Notification.Name("openHotKeyEditor")
    static let openSymbolsEditor = Notification.Name("openSymbolsEditor")
    static let showAboutWindow = Notification.Name("showAboutWindow")
} 