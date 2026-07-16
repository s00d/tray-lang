import Foundation
import AppKit

/// Helper for optimized pasteboard operations with exponential backoff
class PasteboardHelper {
    /// Wait for pasteboard change with short exponential backoff.
    /// Exits as soon as changeCount updates; pumps run loop so HUD stays responsive.
    static func waitForPasteboardChange(
        originalCount: Int,
        timeout: TimeInterval = ClipboardConversionTiming.pasteboardChangeTimeout,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let startTime = Date()
        var delay: TimeInterval = 0.001
        
        while Date().timeIntervalSince(startTime) < timeout {
            if pasteboard.changeCount != originalCount {
                return true
            }
            
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(delay))
            
            if delay < 0.008 {
                delay *= 2
            }
        }
        
        return false
    }
}
