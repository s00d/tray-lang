//
//  ExclusionManager.swift
//  tray-lang
//
//  Created by Stephen Radford on 07/05/2016.
//  Copyright © 2016 Cocoon Development Ltd. All rights reserved.
//  Adapted for tray-lang project
//

import Foundation
import AppKit
import UniformTypeIdentifiers

class ExclusionManager: ObservableObject {
    @Published var excludedApps: [ExcludedApp] = []
    
    private let userDefaults = UserDefaults.standard
    private let excludedAppsKey = "QBlockerExcludedApps"
    
    init() {
        loadExcludedApps()
    }
    
    // MARK: - Public Methods
    
    func addExcludedApp(_ app: ExcludedApp) {
        if !excludedApps.contains(app) {
            excludedApps.append(app)
            saveExcludedApps()
        }
    }
    
    func removeExcludedApp(_ app: ExcludedApp) {
        excludedApps.removeAll { $0 == app }
        saveExcludedApps()
    }
    
    func isAppExcluded(bundleID: String) -> Bool {
        return excludedApps.contains { $0.bundleID == bundleID }
    }
    
    func isCurrentAppExcluded() -> Bool {
        guard let currentApp = NSWorkspace.shared.menuBarOwningApplication else {
            return false
        }
        return isAppExcluded(bundleID: currentApp.bundleIdentifier ?? "")
    }
    
    // MARK: - Private Methods
    
    private func loadExcludedApps() {
        if let data = userDefaults.data(forKey: excludedAppsKey),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            excludedApps = apps
        }
    }
    
    private func saveExcludedApps() {
        if let data = try? JSONEncoder().encode(excludedApps) {
            userDefaults.set(data, forKey: excludedAppsKey)
        }
    }
    
    // MARK: - App Selection
    
    func selectApps() -> [ExcludedApp] {
        let panel = NSOpenPanel()
        panel.title = "Choose Applications"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.application]
        
        var selectedApps: [ExcludedApp] = []
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else {
                    continue
                }
                
                let name = FileManager.default.displayName(atPath: url.path)
                let app = ExcludedApp(name: name, bundleID: bundleID, path: url.path)
                selectedApps.append(app)
            }
        }
        
        return selectedApps
    }
} 