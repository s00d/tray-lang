import Foundation
import AppKit

struct AppLayoutRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var appBundleID: String
    var appName: String
    var layoutID: String // ID раскладки, например "com.apple.keylayout.US"
    
    // Вспомогательное свойство для отображения иконки приложения
    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}


