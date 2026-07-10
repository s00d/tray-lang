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
    case diagnostics
    case about
}

struct ContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    @State private var selectedPanel: Panel = .general
    @State private var showingHotKeyEditor = false
    @State private var editingHotKeyType: String = "layout"
    @State private var showingSymbolsEditor = false
    @State private var showingExclusionsView = false
    @State private var showingDefaultLayoutsEditor = false

    var body: some View {
        NavigationSplitView {
            // --- SIDEBAR ---
            List(selection: $selectedPanel) {
                Section(header: Text("Settings")) {
                    Label("General", systemImage: "gear")
                        .tag(Panel.general)
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
                case .diagnostics:
                    DiagnosticsView(coordinator: coordinator)
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingHotKeyEditor) {
            HotKeyEditorView(coordinator: coordinator, hotKeyType: editingHotKeyType)
        }
        .sheet(isPresented: $showingSymbolsEditor) {
            SymbolsEditorView(appCoordinator: coordinator)
        }
        .sheet(isPresented: $showingExclusionsView) {
            ExclusionsView(exclusionManager: coordinator.exclusionManager)
        }
        .sheet(isPresented: $showingDefaultLayoutsEditor) {
            DefaultLayoutsView(
                smartLayoutManager: coordinator.smartLayoutManager,
                keyboardLayoutManager: coordinator.keyboardLayoutManager
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHotKeyEditor)) { notification in
            if let type = notification.object as? String {
                editingHotKeyType = type
            } else {
                editingHotKeyType = "layout"
            }
            showingHotKeyEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openExclusionsView)) { _ in
            showingExclusionsView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSymbolsEditor)) { _ in
            showingSymbolsEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDefaultLayoutsEditor)) { _ in
            showingDefaultLayoutsEditor = true
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
