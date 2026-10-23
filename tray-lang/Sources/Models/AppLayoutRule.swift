import Foundation
import AppKit

struct AppLayoutRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var appBundleID: String
    var appName: String
    var layoutID: String // e.g. com.apple.keylayout.US
    
    var appIcon: NSImage {
        return IconCache.shared.icon(for: appBundleID)
    }
}


