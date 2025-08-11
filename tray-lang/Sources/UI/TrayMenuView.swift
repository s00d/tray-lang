//
//  TrayMenuView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

struct TrayMenuView: View {
    @StateObject private var coordinator: AppCoordinator
    
    init(coordinator: AppCoordinator) {
        self._coordinator = StateObject(wrappedValue: coordinator)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header section
            VStack(spacing: 0) {
                // Layout status
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    Text("Layout: \(coordinator.keyboardLayoutManager.currentLayout)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            
            // Separator
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
            
            // Main menu items
            VStack(spacing: 0) {
                // Hotkey Editor Button
                MenuButton(
                    icon: "keyboard",
                    iconColor: .blue,
                    title: "Hotkey Editor",
                    action: { openHotKeyEditorWindow() }
                )
                
                // Symbols Editor Button
                MenuButton(
                    icon: "character.textbox",
                    iconColor: .green,
                    title: "Symbols Editor",
                    action: { openSymbolsEditorWindow() }
                )
                
                // Separator
                MenuSeparator()
                
                // Auto Launch Toggle
                MenuToggle(
                    icon: "arrow.up.circle",
                    iconColor: .blue,
                    title: "Auto Launch",
                    isOn: Binding(
                        get: { coordinator.autoLaunchManager.isAutoLaunchEnabled() },
                        set: { newValue in
                            if newValue {
                                coordinator.autoLaunchManager.enableAutoLaunch()
                            } else {
                                coordinator.autoLaunchManager.disableAutoLaunch()
                            }
                        }
                    )
                )
                
                // Separator
                MenuSeparator()
                
                // Settings Button
                MenuButton(
                    icon: "gear",
                    iconColor: .orange,
                    title: "Settings",
                    action: { 
                        print("🔍 Settings button in tray pressed")
                        coordinator.showMainWindow() 
                    }
                )
                
                // About Button
                MenuButton(
                    icon: "info.circle",
                    iconColor: .purple,
                    title: "About",
                    action: { showAboutWindow() }
                )
                
                // Separator
                MenuSeparator()
                
                // Quit Button
                MenuButton(
                    icon: "power",
                    iconColor: .red,
                    title: "Quit",
                    action: { NSApplication.shared.terminate(nil) }
                )
            }
        }
        .frame(width: 240)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.3)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
    
    private func openHotKeyEditorWindow() {
        // Сначала показываем главное окно
        coordinator.showMainWindow()
        
        // Отправляем уведомление для открытия редактора горячих клавиш
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openHotKeyEditor, object: nil)
        }
    }
    
    private func openSymbolsEditorWindow() {
        // Сначала показываем главное окно
        coordinator.showMainWindow()
        
        // Отправляем уведомление для открытия редактора символов
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openSymbolsEditor, object: nil)
        }
    }
    
    private func showAboutWindow() {
        // Сначала показываем главное окно
        coordinator.showMainWindow()
        
        // Отправляем уведомление для показа окна About
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .showAboutWindow, object: nil)
        }
    }
}

// MARK: - Custom Menu Components

// Custom menu button with hover effects
struct MenuButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16, height: 16)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(NSColor.controlAccentColor).opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
            
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// Custom menu toggle with hover effects
struct MenuToggle: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 16, height: 16)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(NSColor.controlAccentColor).opacity(0.05) : Color.clear)
        )
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
    }
}

// Custom menu separator
struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }
}

// Расширения для уведомлений
extension Notification.Name {
    static let openHotKeyEditor = Notification.Name("openHotKeyEditor")
    static let openSymbolsEditor = Notification.Name("openSymbolsEditor")
    static let showAboutWindow = Notification.Name("showAboutWindow")
    static let openExclusionsView = Notification.Name("openExclusionsView")
} 