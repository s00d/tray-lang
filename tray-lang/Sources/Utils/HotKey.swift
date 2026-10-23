import Foundation
import Carbon
import AppKit

// MARK: - Hot Key Structure
struct HotKey: Codable, Equatable {
    let keyCode: Int
    let modifiers: [CGEventFlags]
    
    init(keyCode: Int, modifiers: [CGEventFlags]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    /// From a captured key event; nil when it has no modifier (plain keys must not become global hotkeys),
    /// except function keys which are fine on their own.
    init?(keyCode: Int, flags: NSEvent.ModifierFlags) {
        var modifiers: [CGEventFlags] = []
        if flags.contains(.control) { modifiers.append(.maskControl) }
        if flags.contains(.option) { modifiers.append(.maskAlternate) }
        if flags.contains(.shift) { modifiers.append(.maskShift) }
        if flags.contains(.command) { modifiers.append(.maskCommand) }
        let onlyShift = modifiers == [.maskShift]
        guard KeyCodes.isFunctionKey(keyCode) || (!modifiers.isEmpty && !onlyShift) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    static func == (lhs: HotKey, rhs: HotKey) -> Bool {
        lhs.keyCode == rhs.keyCode && Set(lhs.modifiers.map(\.rawValue)) == Set(rhs.modifiers.map(\.rawValue))
    }

    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        let modifierValues = try container.decode([UInt64].self, forKey: .modifiers)
        modifiers = modifierValues.map { CGEventFlags(rawValue: $0) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        let modifierValues = modifiers.map { $0.rawValue }
        try container.encode(modifierValues, forKey: .modifiers)
    }
    
    var description: String {
        // macOS order: ⌃⌥⇧⌘
        let order: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
        let modifierStrings = order.filter { pair in modifiers.contains { $0.contains(pair.0) } }.map(\.1).joined()
        let keyName = KeyCodes.getKeyName(for: keyCode)
        return modifierStrings + keyName
    }
    
    var displayString: String {
        return description
    }
} 