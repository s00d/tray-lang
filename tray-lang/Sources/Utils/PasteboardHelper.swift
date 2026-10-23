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
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(delay))
            delay = min(delay * 2, 0.008)
        } while Date() < deadline
        return nil
    }
}
