import Foundation
import AppKit

/// What `waitForString` reads; NSPasteboard provides it, tests use a fake.
protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: PasteboardReading {}

enum PasteboardHelper {
    /// Waits until the pasteboard changed *and* holds a string.
    /// `clearContents()` bumps `changeCount` before the new data is written, so the
    /// count alone is not enough to know the copy finished.
    static func waitForString(
        changedFrom originalCount: Int,
        timeout: TimeInterval = ClipboardConversionTiming.pasteboardChangeTimeout,
        pasteboard: PasteboardReading = NSPasteboard.general
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
