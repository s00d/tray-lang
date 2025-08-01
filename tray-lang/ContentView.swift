//
//  ContentView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var trayLangManager: TrayLangManager
    
    @State private var showingSymbolsEditor = false
    @State private var showingHotKeyEditor = false
    @State private var showingAboutWindow = false
    @State private var testText = ""
    @State private var transformedText = ""

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text("Tray Lang")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Accessibility status
                HStack(spacing: 6) {
                    Circle()
                        .fill(trayLangManager.accessibilityStatus.color)
                        .frame(width: 8, height: 8)
                    Text(trayLangManager.accessibilityStatus == .granted ? "Active" : "Inactive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main content
            TabView(selection: $selectedTab) {
                // Main tab
                mainTabView
                    .tabItem {
                        Image(systemName: "house")
                        Text("Main")
                    }
                    .tag(0)
                
                // Testing tab
                testingTabView
                    .tabItem {
                        Image(systemName: "text.magnifyingglass")
                        Text("Test")
                    }
                    .tag(1)
            }
        }
        .frame(width: 400, height: 500)
        .sheet(isPresented: $showingHotKeyEditor) {
            HotKeyEditorView(trayLangManager: trayLangManager)
        }
        .sheet(isPresented: $showingSymbolsEditor) {
            SymbolsEditorView(trayLangManager: trayLangManager)
        }
        .sheet(isPresented: $showingAboutWindow) {
            AboutView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHotKeyEditor)) { _ in
            showingHotKeyEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSymbolsEditor)) { _ in
            showingSymbolsEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutWindow)) { _ in
            showingAboutWindow = true
        }
    }
    
    // MARK: - Main tab
    private var mainTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hotkeys
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Hotkeys")
                            .font(.headline)
                        Spacer()
                        Button("Edit") {
                            showingHotKeyEditor = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundColor(.secondary)
                        Text(trayLangManager.hotKey.description)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                

                
                // Permissions
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(trayLangManager.accessibilityStatus.color)
                        Text("Permissions")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Text(trayLangManager.accessibilityStatus.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if trayLangManager.accessibilityStatus == .denied {
                        Button("Request permissions") {
                            trayLangManager.requestAccessibilityPermissions()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Character settings
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "character.textbox")
                            .foregroundColor(.purple)
                        Text("Character settings")
                            .font(.headline)
                        Spacer()
                        Button("Edit") {
                            showingSymbolsEditor = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("Set up character mapping between layouts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    // MARK: - Testing tab
    private var testingTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Testing")
                        .font(.headline)
                    
                    TextField("Enter text for testing", text: $testText)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Transform") {
                        let isRussian = trayLangManager.detectLanguage(testText)
                        transformedText = trayLangManager.transformText(testText, fromRussian: isRussian)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(testText.isEmpty)
                    
                    if !transformedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Result:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(transformedText)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

// MARK: - Helper components
struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}






#Preview {
    ContentView()
        .environmentObject(TrayLangManager())
}
