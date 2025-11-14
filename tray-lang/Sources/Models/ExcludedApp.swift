//
//  ExcludedApp.swift
//  tray-lang
//
//  Created by Stephen Radford on 07/05/2016.
//  Copyright © 2016 Cocoon Development Ltd. All rights reserved.
//  Adapted for tray-lang project
//

import Foundation
import AppKit

struct ExcludedApp: Identifiable, Codable, Equatable {
    var id: UUID
    
    /// The name of the app that will be displayed as a label
    var name: String
    
    /// The bundle ID of the app. e.g. uk.co.wearecocoon.QBlocker
    var bundleID: String
    
    /// The path to the app
    var path: String
    
    // Вспомогательное свойство для получения иконки приложения
    var appIcon: NSImage? {
        // Ищем приложение по bundleID
        guard let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleID) else {
            // Если не нашли, можно попробовать по сохраненному пути как фолбэк
            if FileManager.default.fileExists(atPath: self.path) {
                return NSWorkspace.shared.icon(forFile: self.path)
            }
            return nil
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    init(name: String, bundleID: String, path: String) {
        self.id = UUID()
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }
    
    static func == (lhs: ExcludedApp, rhs: ExcludedApp) -> Bool {
        return lhs.bundleID == rhs.bundleID
    }
} 