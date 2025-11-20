import Foundation
import AppKit

/// Helper for optimized pasteboard operations with exponential backoff
class PasteboardHelper {
    /// Wait for pasteboard change with exponential backoff
    static func waitForPasteboardChange(originalCount: Int, timeout: TimeInterval = 0.3) -> Bool {
        let startTime = Date()
        var delay: useconds_t = 1000 // Начинаем с 1мс
        
        while Date().timeIntervalSince(startTime) < timeout {
            if NSPasteboard.general.changeCount != originalCount {
                return true
            }
            
            usleep(delay) // Спим, не нагружая CPU
            
            // Постепенно увеличиваем интервал опроса (backoff), но не более 20мс
            if delay < 20000 {
                delay *= 2
            }
        }
        
        return false
    }
}

