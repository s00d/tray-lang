import Foundation

/// What the hotkey converts between.
/// Built-in profiles are not stored: they name two macOS keyboard layouts and the
/// key → character table is read from the system (`SystemKeyboardLayouts`).
/// Only custom profiles carry their own `mapping` and are persisted.
struct ConversionProfile: Identifiable, Codable, Hashable {
    static let autoID = "auto"
    private static let systemPrefix = "layout:"

    var id: String
    var name: String
    /// Latin side (the keys the mapping starts from). Nil for custom profiles.
    var sourceLayoutID: String?
    /// Non-latin / other side. Nil for Auto (resolved at runtime) and custom profiles.
    var targetLayoutID: String?
    /// Only used by custom profiles.
    var mapping: [String: String]

    var isAuto: Bool { id == Self.autoID }
    var isEditable: Bool { !isAuto && targetLayoutID == nil }

    static let auto = ConversionProfile(
        id: autoID,
        name: "Auto (enabled layouts)",
        sourceLayoutID: nil,
        targetLayoutID: nil,
        mapping: [:]
    )

    static func system(target layoutID: String, source: String = SystemKeyboardLayouts.abcLayoutID, name: String? = nil) -> ConversionProfile {
        ConversionProfile(
            id: systemPrefix + layoutID,
            name: name ?? SystemKeyboardLayouts.localizedName(ofLayoutID: layoutID) ?? layoutID,
            sourceLayoutID: source,
            targetLayoutID: layoutID,
            mapping: [:]
        )
    }

    static func custom(name: String, mapping: [String: String]) -> ConversionProfile {
        ConversionProfile(id: UUID().uuidString, name: name, sourceLayoutID: nil, targetLayoutID: nil, mapping: mapping)
    }

    /// Rebuilds a built-in profile from its id (used when restoring the selection).
    static func builtIn(id: String) -> ConversionProfile? {
        if id == autoID { return .auto }
        guard id.hasPrefix(systemPrefix) else { return nil }
        let layoutID = String(id.dropFirst(systemPrefix.count))
        guard SystemKeyboardLayouts.keyTable(layoutID: layoutID) != nil else { return nil }
        return .system(target: layoutID)
    }

    // Older builds stored `isEditable` and UUID ids; both decode into this shape.
    private enum CodingKeys: String, CodingKey {
        case id, name, sourceLayoutID, targetLayoutID, mapping, isEditable
    }

    init(id: String, name: String, sourceLayoutID: String?, targetLayoutID: String?, mapping: [String: String]) {
        self.id = id
        self.name = name
        self.sourceLayoutID = sourceLayoutID
        self.targetLayoutID = targetLayoutID
        self.mapping = mapping
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceLayoutID = try container.decodeIfPresent(String.self, forKey: .sourceLayoutID)
        targetLayoutID = try container.decodeIfPresent(String.self, forKey: .targetLayoutID)
        mapping = try container.decodeIfPresent([String: String].self, forKey: .mapping) ?? [:]
        // Legacy built-in templates (isEditable == false) are dropped on load.
        if try container.decodeIfPresent(Bool.self, forKey: .isEditable) == false {
            throw DecodingError.dataCorruptedError(forKey: .isEditable, in: container, debugDescription: "legacy built-in")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(sourceLayoutID, forKey: .sourceLayoutID)
        try container.encodeIfPresent(targetLayoutID, forKey: .targetLayoutID)
        try container.encode(mapping, forKey: .mapping)
    }
}
