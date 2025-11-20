import Foundation
import AppKit

class IconCache {
    static let shared = IconCache()
    
    private var cache = NSCache<NSString, NSImage>()
    
    private init() {
        // Настраиваем лимиты кэша
        cache.countLimit = 100 // Максимум 100 иконок
        cache.totalCostLimit = 10 * 1024 * 1024 // 10 MB
    }
    
    func icon(for bundleID: String) -> NSImage {
        if let cached = cache.object(forKey: bundleID as NSString) {
            return cached
        }
        
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32) // Оптимизируем размер сразу
            cache.setObject(icon, forKey: bundleID as NSString)
            return icon
        }
        
        // Fallback иконка
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}

