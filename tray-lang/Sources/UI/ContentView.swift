//
//  ContentView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

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

    var body: some View {
        NavigationSplitView {
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
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .showAboutWindow)) { _ in
            selectedPanel = .about
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPanel {
        case .general:
            GeneralSettingsView(coordinator: coordinator)
        case .hotkeyEditorLayout:
            HotKeyEditorView(coordinator: coordinator, hotKeyType: "layout")
        case .hotkeyEditorSpell:
            HotKeyEditorView(coordinator: coordinator, hotKeyType: "spell")
        case .symbolsEditor:
            SymbolsEditorView(appCoordinator: coordinator)
        case .exclusionsEditor:
            ExclusionsView(exclusionManager: coordinator.exclusionManager)
        case .defaultLayoutsEditor:
            DefaultLayoutsView(
                smartLayoutManager: coordinator.smartLayoutManager,
                keyboardLayoutManager: coordinator.keyboardLayoutManager
            )
        case .diagnostics:
            DiagnosticsView(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .about:
            AboutSettingsView()
        }
    }
}

extension Notification.Name {
    static let showAboutWindow = Notification.Name("showAboutWindow")
}

#Preview {
    ContentView(coordinator: AppCoordinator())
}
