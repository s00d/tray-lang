import Foundation
import Carbon

// MARK: - Key Information Structure
struct KeyInfo {
    let keyCode: Int
    let name: String
    let displayName: String
}

// MARK: - Key Utils
class KeyUtils {
    private static var cachedKeyCodes: [KeyInfo]?
    private static var lastCacheTime: Date = Date.distantPast
    private static let cacheTimeout: TimeInterval = 5.0 // 5 seconds
    
    static func getAvailableKeyCodes() -> [KeyInfo] {
        // Check cache
        let now = Date()
        if let cached = cachedKeyCodes, 
           now.timeIntervalSince(lastCacheTime) < cacheTimeout {
            return cached
        }
        
        var keyInfos: [KeyInfo] = []
        
        // 1. Get keys from system via Carbon API (not implemented)
        if let systemKeys = getSystemKeyCodes() {
            keyInfos.append(contentsOf: systemKeys)
            print("[KeyUtils] Got \(systemKeys.count) keys from system API")
        }
        
        // 2. Fallback
        if keyInfos.isEmpty {
            keyInfos = getFallbackKeyCodes()
            print("[KeyUtils] Using fallback keys")
        }
        
        // Sort by keyCode
        let sortedKeys = keyInfos.sorted { $0.keyCode < $1.keyCode }
        print("[KeyUtils] Total available keys: \(sortedKeys.count)")
        
        // Cache
        cachedKeyCodes = sortedKeys
        lastCacheTime = now
        
        return sortedKeys
    }
    
    static func getAvailableModifiers() -> [(CGEventFlags, String)] {
        return [
            (.maskCommand, "⌘"),
            (.maskShift, "⇧"),
            (.maskAlternate, "⌥"),
            (.maskControl, "⌃")
        ]
    }
    
    // MARK: - Private Methods
    private static func getSystemKeyCodes() -> [KeyInfo]? {
        // Not implemented
        return nil
    }
    
    private static func getFallbackKeyCodes() -> [KeyInfo] {
        return KeyCodes.keyNames.map { (keyCode, name) in
            KeyInfo(keyCode: keyCode, name: name, displayName: name)
        }
    }
} 