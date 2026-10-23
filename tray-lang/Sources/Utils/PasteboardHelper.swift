import Foundation
import AppKit

enum PasteboardHelper {
    /// Waits until the pasteboard changed *and* holds a string.
    /// `clearContents()` bumps `changeCount` before the new data is written, so the
    /// count alone is not enough to know the copy finished.
    static func waitForString(
        changedFrom originalCount: Int,
        timeout: TimeInterval = ClipboardConversionTiming.pasteboardChangeTimeout,
        pasteboard: NSPasteboard = .general
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var delay: TimeInterval = 0.001
        repeat {
            if pasteboard.changeCount != originalCount, let string = pasteboard.string(forType: .string) {
                return string
            }
            if Thread.isMainThread {
                // Keep the UI (HUD) responsive while waiting.
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(delay))
            } else {
                // A background run loop has no sources and returns at once; sleep instead of spinning.
                Thread.sleep(forTimeInterval: delay)
            }
            delay = min(delay * 2, 0.008)
        } while Date() < deadline
        return nil
    }
}
