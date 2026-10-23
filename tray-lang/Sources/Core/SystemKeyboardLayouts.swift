import Foundation
import Carbon

/// Reads real key → character tables from macOS keyboard layouts (`UCKeyTranslate`),
/// so conversion profiles match what the user's keyboard actually types.
enum SystemKeyboardLayouts {
    static let abcLayoutID = "com.apple.keylayout.ABC"

    /// Printable keys of an ANSI/ISO Mac keyboard, row by row. 10 is the ISO key left of 1 (§ on ABC).
    static let printableKeyCodes: [UInt16] = [
        50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24,
        12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42,
        0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39,
        6, 7, 8, 9, 11, 45, 46, 43, 47, 44,
        10,
    ]

    /// Letter keys in QWERTY order a…z, used to probe which layout is which.
    static let letterKeyCodes: [UInt16] = [
        0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,
    ]

    /// Built-in profile list: the layouts the old hand-written templates targeted, plus both Russian variants.
    static let commonLayoutIDs: [String] = [
        "com.apple.keylayout.Russian",
        "com.apple.keylayout.RussianWin",
        "com.apple.keylayout.Russian-Phonetic",
        "com.apple.keylayout.Ukrainian-PC",
        "com.apple.keylayout.Ukrainian",
        "com.apple.keylayout.Byelorussian",
        "com.apple.keylayout.Bulgarian",
        "com.apple.keylayout.Bulgarian-Phonetic",
        "com.apple.keylayout.Greek",
        "com.apple.keylayout.Hebrew",
        "com.apple.keylayout.Arabic",
        "com.apple.keylayout.German",
        "com.apple.keylayout.French",
        "com.apple.keylayout.Spanish-ISO",
        "com.apple.keylayout.Portuguese",
        "com.apple.keylayout.Italian",
        "com.apple.keylayout.Swedish",
        "com.apple.keylayout.Finnish",
        "com.apple.keylayout.Danish",
        "com.apple.keylayout.Norwegian",
        "com.apple.keylayout.Turkish-QWERTY-PC",
        "com.apple.keylayout.British",
        "com.apple.keylayout.Dvorak",
        "com.apple.keylayout.Colemak",
    ]

    /// Every installed keyboard layout except the latin source ones, sorted by name — for "Other layouts…".
    static func allInstalledLayouts() -> [(id: String, name: String)] {
        allLayoutNames()
            .filter { $0.key != abcLayoutID && $0.key != "com.apple.keylayout.US" }
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    struct KeyOutput: Equatable {
        let plain: String
        let shifted: String
    }

    private static var cache: [String: [UInt16: KeyOutput]] = [:]
    private static var nameCache: [String: String]?
    private static let cacheLock = NSLock()

    /// HIToolbox aborts when TIS is used from two threads at once; Apple: "call TIS/TSM API on the main thread".
    private static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    // MARK: - Input sources

    static func inputSources(includeAllInstalled: Bool) -> [TISInputSource] {
        onMain {
            let filter = [
                kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
            ] as CFDictionary
            return TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource] ?? []
        }
    }

    static func identifier(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    static func localizedName(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static var enabledCache: [String]?
    private static var enabledObserver: NSObjectProtocol?

    /// Enabled keyboard layouts (what the user switches between), in system order.
    /// Cached until macOS reports a change in System Settings › Keyboard › Input Sources.
    static func enabledLayoutIDs() -> [String] {
        cacheLock.lock()
        if let enabledCache {
            cacheLock.unlock()
            return enabledCache
        }
        cacheLock.unlock()
        let ids = onMain { () -> [String] in
            if enabledObserver == nil {
                enabledObserver = DistributedNotificationCenter.default().addObserver(
                    forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                    object: nil, queue: nil
                ) { _ in
                    cacheLock.lock()
                    enabledCache = nil
                    cacheLock.unlock()
                }
            }
            return inputSources(includeAllInstalled: false).compactMap(identifier(of:))
        }
        cacheLock.lock()
        enabledCache = ids
        cacheLock.unlock()
        return ids
    }

    static func localizedName(ofLayoutID layoutID: String) -> String? {
        allLayoutNames()[layoutID]
    }

    /// id → localized name for every installed layout; read once, layouts don't get renamed at runtime.
    private static func allLayoutNames() -> [String: String] {
        cacheLock.lock()
        if let nameCache {
            cacheLock.unlock()
            return nameCache
        }
        cacheLock.unlock()
        let names = onMain {
            Dictionary(
                inputSources(includeAllInstalled: true).compactMap { source in
                    identifier(of: source).map { ($0, localizedName(of: source) ?? $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
        cacheLock.lock()
        nameCache = names
        cacheLock.unlock()
        return names
    }

    // MARK: - Key tables

    /// Characters produced by every printable key, without and with Shift. Nil when the layout is unknown.
    static func keyTable(layoutID: String) -> [UInt16: KeyOutput]? {
        cacheLock.lock()
        if let cached = cache[layoutID] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let table: [UInt16: KeyOutput]? = onMain {
            inputSources(includeAllInstalled: true)
                .first(where: { identifier(of: $0) == layoutID })
                .flatMap(keyTable(source:))
        }
        guard let table else { return nil }

        cacheLock.lock()
        cache[layoutID] = table
        cacheLock.unlock()
        return table
    }

    private static func keyTable(source: TISInputSource) -> [UInt16: KeyOutput]? {
        guard let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }

        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            var table: [UInt16: KeyOutput] = [:]
            for keyCode in printableKeyCodes {
                table[keyCode] = KeyOutput(
                    plain: translate(layout, keyCode: keyCode, modifiers: 0),
                    shifted: translate(layout, keyCode: keyCode, modifiers: UInt32(shiftKey >> 8))
                )
            }
            return table
        }
    }

    private static func translate(_ layout: UnsafePointer<UCKeyboardLayout>, keyCode: UInt16, modifiers: UInt32) -> String {
        var deadKeyState: UInt32 = 0
        var string = translate(layout, keyCode: keyCode, modifiers: modifiers, deadKeyState: &deadKeyState)
        // Dead key (´ ` ^ ¨ on German, Nordic, Spanish…): the key alone types its accent when followed by Space.
        if string.isEmpty, deadKeyState != 0 {
            string = translate(layout, keyCode: 49, modifiers: 0, deadKeyState: &deadKeyState)
        }
        // Control characters and lone whitespace are not useful mapping targets.
        guard !string.isEmpty,
              string.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
              !string.unicodeScalars.allSatisfy(\.properties.isWhitespace) else {
            return ""
        }
        return string
    }

    private static func translate(
        _ layout: UnsafePointer<UCKeyboardLayout>,
        keyCode: UInt16,
        modifiers: UInt32,
        deadKeyState: inout UInt32
    ) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifiers,
            UInt32(LMGetKbdType()),
            0,
            &deadKeyState,
            buffer.count,
            &length,
            &buffer
        )
        guard status == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: length)
    }

    // MARK: - Mappings

    /// Same-key mapping `source char → target char` for two layouts. Identical pairs are skipped.
    static func mapping(from sourceLayoutID: String, to targetLayoutID: String) -> [String: String]? {
        guard let source = keyTable(layoutID: sourceLayoutID),
              let target = keyTable(layoutID: targetLayoutID) else {
            return nil
        }
        return mapping(source: source, target: target)
    }

    static func mapping(source: [UInt16: KeyOutput], target: [UInt16: KeyOutput]) -> [String: String] {
        var result: [String: String] = [:]
        for keyCode in printableKeyCodes {
            guard let from = source[keyCode], let to = target[keyCode] else { continue }
            for (a, b) in [(from.plain, to.plain), (from.shifted, to.shifted)]
            where !a.isEmpty && !b.isEmpty && a != b && result[a] == nil {
                result[a] = b
            }
        }
        return result
    }

    /// A layout that types all 26 ASCII letters without modifiers (ABC, US, Dvorak, Colemak, QWERTZ, AZERTY…).
    private static var latinCache: [String: Bool] = [:]

    static func isLatin(layoutID: String) -> Bool {
        cacheLock.lock()
        let cached = latinCache[layoutID]
        cacheLock.unlock()
        if let cached { return cached }
        guard let table = keyTable(layoutID: layoutID) else { return false }
        let letters = Set(table.values.compactMap { $0.plain.count == 1 ? $0.plain.first : nil }.filter { $0.isASCII && $0.isLowercase })
        let isLatin = letters.count == 26
        cacheLock.lock()
        latinCache[layoutID] = isLatin
        cacheLock.unlock()
        return isLatin
    }

    /// The enabled latin + non-latin pair used by the Auto profile, e.g. (ABC, Russian).
    static func enabledAutoPair(enabled: [String] = enabledLayoutIDs()) -> (source: String, target: String)? {
        guard let target = enabled.first(where: { !isLatin(layoutID: $0) }) else { return nil }
        let source = enabled.first(where: isLatin(layoutID:)) ?? abcLayoutID
        return (source, target)
    }

    /// Picks the enabled layout whose `keyCode` (no modifiers) types `character`.
    static func enabledLayoutID(typing character: String, atKeyCode keyCode: UInt16, enabled: [String] = enabledLayoutIDs()) -> String? {
        enabled.first { keyTable(layoutID: $0)?[keyCode]?.plain == character }
    }
}
