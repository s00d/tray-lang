import AppKit

/// Small app icons for settings lists. Keeps only the 32 pt representation (app icons carry
/// many sizes up to 1024 px), and remembers apps that aren't installed so they cost one lookup.
final class IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let size = NSSize(width: 32, height: 32)
    private lazy var placeholder = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()

    private init() {
        cache.countLimit = 400
    }

    func icon(for bundleID: String) -> NSImage {
        if let cached = cache.object(forKey: bundleID as NSString) {
            return cached
        }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map(smallIcon(at:)) ?? placeholder
        cache.setObject(image, forKey: bundleID as NSString)
        return image
    }

    private func smallIcon(at url: URL) -> NSImage {
        let full = NSWorkspace.shared.icon(forFile: url.path)
        let rect = NSRect(origin: .zero, size: size)
        guard let rep = full.bestRepresentation(for: rect, context: nil, hints: [.ctm: AffineTransform(scale: 2)]) else {
            full.size = size
            return full
        }
        let small = NSImage(size: size)
        small.addRepresentation(rep)
        return small
    }
}
