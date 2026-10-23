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

class ExclusionManager: ObservableObject {
    @Published var excludedApps: [ExcludedApp] = []
    
    private let userDefaults = AppDefaults.store
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
}
