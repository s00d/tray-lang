import Foundation
import AppKit

/// Helper for optimized pasteboard operations with exponential backoff
class PasteboardHelper {
    /// Wait for pasteboard change with exponential backoff.
    /// Pumps the run loop so UI (conversion HUD) can stay visible during mode-3 waits.
    static func waitForPasteboardChange(originalCount: Int, timeout: TimeInterval = 0.3) -> Bool {
        let startTime = Date()
        var delay: TimeInterval = 0.001
        
        while Date().timeIntervalSince(startTime) < timeout {
            if NSPasteboard.general.changeCount != originalCount {
                return true
            }
            
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(delay))
            
            if delay < 0.02 {
                delay *= 2
            }
        }
        
        return false
    }
}

