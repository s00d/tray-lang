import Foundation
import Carbon

// MARK: - Hot Key Structure
struct HotKey: Codable {
    let keyCode: Int
    let modifiers: [CGEventFlags]
    
    init(keyCode: Int, modifiers: [CGEventFlags]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
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
        let modifierStrings = modifiers.map { modifier -> String in
            switch modifier {
            case .maskCommand: return "⌘"
            case .maskShift: return "⇧"
            case .maskAlternate: return "⌥"
            case .maskControl: return "⌃"
            default: return ""
            }
        }.joined()
        let keyName = KeyCodes.getKeyName(for: keyCode)
        return modifierStrings + keyName
    }
    
    var displayString: String {
        return description
    }
} 