import Foundation
import AppKit

class AppleScriptCache {
    static let shared = AppleScriptCache()
    
    // Кэшируем скрипт для завершения приложения
    lazy var quitScript: NSAppleScript? = {
        // Этот скрипт будет заменен динамически при использовании
        return nil
    }()
    
    private init() {}
    
    func executeQuit(for appName: String) -> Bool {
        // Создаем скрипт для конкретного приложения
        let scriptSource = """
        tell application "\(appName)" to quit
        """
        
        guard let script = NSAppleScript(source: scriptSource) else {
            return false
        }
        
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        
        if let error = error {
            debugLog("❌ AppleScript error: \(error)")
            return false
        }
        
        return true
    }
}

