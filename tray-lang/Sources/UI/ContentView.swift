//
//  ContentView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var coordinator: AppCoordinator
    @ObservedObject private var hotKeyManager: HotKeyManager
    
    @State private var showingSymbolsEditor = false
    @State private var showingHotKeyEditor = false
    @State private var showingAboutWindow = false
    @State private var showingExclusionsView = false
    @State private var testText = ""
    @State private var transformedText = ""

    @State private var selectedTab = 0

    init(coordinator: AppCoordinator) {
        self._coordinator = StateObject(wrappedValue: coordinator)
        self.hotKeyManager = coordinator.hotKeyManager
    }

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
                
                // Status indicators
                HStack(spacing: 8) {
                    // Hotkey status
                    Circle()
                        .fill(coordinator.hotKeyManager.isEnabled ? .green : .red)
                        .frame(width: 12, height: 12)
                        .help(coordinator.hotKeyManager.isEnabled ? "Hotkey monitoring active" : "Hotkey monitoring inactive")
                        .animation(.easeInOut(duration: 0.2), value: coordinator.hotKeyManager.isEnabled)
                    
                    // Accessibility status
                    Circle()
                        .fill(coordinator.accessibilityManager.accessibilityStatus.color)
                        .frame(width: 12, height: 12)
                        .help(coordinator.accessibilityManager.accessibilityStatus.description)
                        .animation(.easeInOut(duration: 0.2), value: coordinator.accessibilityManager.accessibilityStatus)
                }
                .id("status-indicators")
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
            HotKeyEditorView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingSymbolsEditor) {
            SymbolsEditorView(appCoordinator: coordinator)
        }
        .sheet(isPresented: $showingAboutWindow) {
            AboutView()
        }
        .sheet(isPresented: $showingExclusionsView) {
            ExclusionsView(exclusionManager: coordinator.exclusionManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHotKeyEditor)) { _ in
            showingHotKeyEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openExclusionsView)) { _ in
            showingExclusionsView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSymbolsEditor)) { _ in
            showingSymbolsEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutWindow)) { _ in
            showingAboutWindow = true
        }
    }
    
    // MARK: - Main Tab View
    private var mainTabView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hotkey & Symbols Configuration
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundColor(.blue)
                        Text("Hotkey & Symbols Configuration")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Hotkey:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(coordinator.hotKeyManager.hotKey.displayString) {
                                showingHotKeyEditor = true
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        HStack {
                            Text("Symbols:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Edit Symbols") {
                                showingSymbolsEditor = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // QBlocker Configuration
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.orange)
                        Text("QBlocker Protection")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Block accidental Cmd+Q")
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $coordinator.qBlockerManager.isEnabled)
                        }
                        
                        if coordinator.qBlockerManager.isEnabled {
                            HStack {
                                Text("Delay (seconds):")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Stepper("\(coordinator.qBlockerManager.delay)", value: $coordinator.qBlockerManager.delay, in: 1...5)
                                    .onChange(of: coordinator.qBlockerManager.delay) { _, _ in
                                        coordinator.qBlockerManager.saveSettings()
                                    }
                            }
                            
                            HStack {
                                Text("Accidental quits prevented:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(coordinator.qBlockerManager.accidentalQuits)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            
                            Button("Manage Exclusions") {
                                showingExclusionsView = true
                            }
                            .buttonStyle(.bordered)
                            .help("Configure which applications should be excluded from QBlocker protection")
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding()
        }
    }
    
    // MARK: - Testing tab
    private var testingTabView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Test Text Conversion")
                    .font(.headline)
                
                Text("Enter text to test the conversion:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                TextField("Enter text here...", text: $testText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                
                Button("Convert") {
                    transformedText = coordinator.textTransformer.transformText(testText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(testText.isEmpty)
                
                if !transformedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Result:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(transformedText)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
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
    ContentView(coordinator: AppCoordinator())
}
