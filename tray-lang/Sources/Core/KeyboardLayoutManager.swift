import Foundation
import AppKit
import Carbon

struct KeyboardLayout: Identifiable, Hashable {
    var id: String              // com.apple.keylayout.Russian
    var localizedName: String   // Russian / Русская
    var shortName: String       // RU
    /// The flag/letter icon macOS shows in its Input menu.
    var iconURL: URL?
}

/// The user's input sources and the selected one. Main thread only (TIS requires it).
final class KeyboardLayoutManager: ObservableObject {
    @Published private(set) var currentLayout: KeyboardLayout?
    @Published private(set) var availableLayouts: [KeyboardLayout] = []

    private var observers: [NSObjectProtocol] = []

    init() {
        reload()
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
                self?.refreshCurrentLayout()
            },
            center.addObserver(forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            },
        ]
    }

    deinit {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
    }

    private func reload() {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        // Only what the user can switch to: the same list as the system Input menu.
        availableLayouts = sources.filter(Self.isSelectable).compactMap(Self.layout(from:))
        refreshCurrentLayout()
    }

    private func refreshCurrentLayout() {
        let layout = TISCopyCurrentKeyboardInputSource().flatMap { Self.layout(from: $0.takeRetainedValue()) }
        if layout != currentLayout {
            currentLayout = layout
        }
    }

    /// Read straight from the system, in case the change notification hasn't arrived yet.
    var currentLayoutID: String? {
        TISCopyCurrentKeyboardInputSource().flatMap { SystemKeyboardLayouts.identifier(of: $0.takeRetainedValue()) }
    }

    /// Selects an enabled input source. False when it is not enabled or selection failed.
    @discardableResult
    func switchToLayout(id layoutID: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: layoutID] as CFDictionary
        guard let source = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first,
              TISSelectInputSource(source) == noErr else { return false }
        refreshCurrentLayout()
        return true
    }

    // MARK: - Reading input sources

    private static func isSelectable(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    private static func layout(from source: TISInputSource) -> KeyboardLayout? {
        guard let id = SystemKeyboardLayouts.identifier(of: source) else { return nil }
        let name = SystemKeyboardLayouts.localizedName(of: source) ?? id
        let language = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .flatMap { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] }?.first
        let shortName = language.map(normalizeLanguageCode) ?? extractShortNameFromLayoutID(id)
        let iconURL = TISGetInputSourceProperty(source, kTISPropertyIconImageURL)
            .map { Unmanaged<CFURL>.fromOpaque($0).takeUnretainedValue() as URL }
        return KeyboardLayout(id: id, localizedName: name, shortName: shortName.isEmpty ? "?" : shortName, iconURL: iconURL)
    }

    /// ISO 639 language → menu bar label. Regional codes keep the region where it reads better (en-GB → GB).
    static func normalizeLanguageCode(_ code: String) -> String {
        let special: [String: String] = [
            "en": "EN", "en-GB": "GB", "ja": "JP", "zh": "CN", "zh-Hans": "CN", "zh-Hant": "TW", "ko": "KR",
            "he": "IL", "hi": "IN", "uk": "UA", "cs": "CZ", "sv": "SE", "da": "DK",
        ]
        if let mapped = special[code] { return mapped }
        let base = String(code.split(separator: "-").first ?? Substring(code))
        return special[base] ?? String(base.prefix(2)).uppercased()
    }

    /// Fallback when a source reports no language: guess from its ID.
    static func extractShortNameFromLayoutID(_ layoutID: String) -> String {
        let patterns: [(String, String)] = [
            ("abc", "EN"), ("us", "EN"), ("russian", "RU"), ("french", "FR"), ("german", "DE"), ("spanish", "ES"),
            ("italian", "IT"), ("portuguese", "PT"), ("japanese", "JP"), ("chinese", "CN"), ("korean", "KR"),
            ("arabic", "AR"), ("hebrew", "IL"), ("hindi", "IN"), ("ukrainian", "UA"), ("polish", "PL"), ("czech", "CZ"),
            ("turkish", "TR"), ("dutch", "NL"), ("swedish", "SE"), ("danish", "DK"), ("norwegian", "NO"), ("finnish", "FI"),
        ]
        let lowercased = layoutID.lowercased()
        // Longer patterns first: "russian" contains "us".
        if let match = patterns.sorted(by: { $0.0.count > $1.0.count }).first(where: { lowercased.contains($0.0) }) {
            return match.1
        }
        return layoutID.split(separator: ".").last.map { String($0.prefix(2)).uppercased() } ?? ""
    }
}
