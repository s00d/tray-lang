//
//  ContentView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

// Define panels for navigation
enum Panel: Hashable {
    case general
    case hotkeyEditorLayout
    case hotkeyEditorSpell
    case symbolsEditor
    case exclusionsEditor
    case defaultLayoutsEditor
    case diagnostics
    case about
}

struct ContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    @State private var selectedPanel: Panel = .general
    @State private var editingHotKeyType: String = "layout"

    var body: some View {
        NavigationSplitView {
            // --- SIDEBAR ---
            List(selection: $selectedPanel) {
                Section(header: Text("Settings")) {
                    Label("General", systemImage: "gear")
                        .tag(Panel.general)
                    Label("Main Hotkey", systemImage: "keyboard")
                        .tag(Panel.hotkeyEditorLayout)
                    Label("Spell Check Hotkey", systemImage: "text.badge.checkmark")
                        .tag(Panel.hotkeyEditorSpell)
                    Label("Symbols & Languages", systemImage: "pencil")
                        .tag(Panel.symbolsEditor)
                    Label("Default Rules", systemImage: "list.bullet.rectangle.portrait")
                        .tag(Panel.defaultLayoutsEditor)
                    Label("Exclusions", systemImage: "shield.slash")
                        .tag(Panel.exclusionsEditor)
                }
                
                Section(header: Text("Tools")) {
                    Label("Diagnostics", systemImage: "ladybug")
                        .tag(Panel.diagnostics)
                }
                
                Section {
                    Label("About", systemImage: "info.circle")
                        .tag(Panel.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            Group {
                switch selectedPanel {
                case .general:
                    GeneralSettingsView(coordinator: coordinator)
                case .hotkeyEditorLayout:
                    HotKeyEditorView(coordinator: coordinator, hotKeyType: "layout") {
                        selectedPanel = .general
                    }
                case .hotkeyEditorSpell:
                    HotKeyEditorView(coordinator: coordinator, hotKeyType: "spell") {
                        selectedPanel = .general
                    }
                case .symbolsEditor:
                    SymbolsEditorView(appCoordinator: coordinator) {
                        selectedPanel = .general
                    }
                case .exclusionsEditor:
                    ExclusionsView(exclusionManager: coordinator.exclusionManager) {
                        selectedPanel = .general
                    }
                case .defaultLayoutsEditor:
                    DefaultLayoutsView(
                        smartLayoutManager: coordinator.smartLayoutManager,
                        keyboardLayoutManager: coordinator.keyboardLayoutManager
                    ) {
                        selectedPanel = .general
                    }
                case .diagnostics:
                    DiagnosticsView(coordinator: coordinator)
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .openHotKeyEditor)) { notification in
            if let type = notification.object as? String {
                editingHotKeyType = type
            } else {
                editingHotKeyType = "layout"
            }
            selectedPanel = editingHotKeyType == "spell" ? .hotkeyEditorSpell : .hotkeyEditorLayout
        }
        .onReceive(NotificationCenter.default.publisher(for: .openExclusionsView)) { _ in
            selectedPanel = .exclusionsEditor
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSymbolsEditor)) { _ in
            selectedPanel = .symbolsEditor
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDefaultLayoutsEditor)) { _ in
            selectedPanel = .defaultLayoutsEditor
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutWindow)) { _ in
            selectedPanel = .about
        }
    }
}

// Notifications for opening modal windows
extension Notification.Name {
    static let openDefaultLayoutsEditor = Notification.Name("openDefaultLayoutsEditor")
    static let showAboutWindow = Notification.Name("showAboutWindow")
    static let openHotKeyEditor = Notification.Name("openHotKeyEditor")
    static let openSymbolsEditor = Notification.Name("openSymbolsEditor")
    static let openExclusionsView = Notification.Name("openExclusionsView")
}

#Preview {
    ContentView(coordinator: AppCoordinator())
}
