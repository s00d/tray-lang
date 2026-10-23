import Foundation

/// Converts text typed in the wrong keyboard layout.
///
/// Every character is converted key-for-key between the two layouts of the active profile.
/// Characters that exist only on one side (letters, `@`, `№`…) always flip to the other side,
/// so mixed text like `фыва ghjjk` converts both ways at once. Characters that exist on
/// both sides (`.`, `,`, `;`, `"`…) follow the word they are in; words without a hint follow
/// the nearest word, then the layout the text was typed in.
final class TextTransformer: ObservableObject {
    enum Direction: Equatable {
        /// Latin (source) → other layout (target), e.g. `ghbdtn` → `привет`.
        case toTarget
        /// Other layout → latin, e.g. `руддщ` → `hello`.
        case toSource
    }

    struct Conversion: Equatable {
        let text: String
        /// Which side the last converted word ended on — the layout to switch to afterwards.
        let endsOn: Direction?
    }

    /// Mapping tables for one profile, resolved against the system layouts.
    struct ResolvedProfile {
        let forward: [String: String]
        let inverse: [String: String]
        let sourceLayoutID: String?
        let targetLayoutID: String?
        /// Longest key in Unicode scalars (Hebrew/Arabic keys can type 2–3 scalars).
        let maxKeyLength: Int

        init(forward: [String: String], sourceLayoutID: String?, targetLayoutID: String?) {
            self.forward = forward
            self.inverse = TextTransformer.inverseMapping(of: forward)
            self.maxKeyLength = max(1, (Array(forward.keys) + Array(forward.values)).map(\.unicodeScalars.count).max() ?? 1)
            self.sourceLayoutID = sourceLayoutID
            self.targetLayoutID = targetLayoutID
        }
    }

    @Published private(set) var customProfiles: [ConversionProfile] = []
    @Published var activeProfileID: String = ConversionProfile.autoID {
        didSet {
            guard activeProfileID != oldValue else { return }
            defaults?.set(activeProfileID, forKey: DefaultsKeys.activeProfileID)
            resolvedCache = nil
        }
    }

    private let defaults: UserDefaults?
    private let enabledLayouts: () -> [String]
    private var resolvedCache: (key: String, value: ResolvedProfile?)?

    /// App instance: persisted custom profiles and selection, live system layouts.
    init(defaults: UserDefaults = AppDefaults.store) {
        self.defaults = defaults
        self.enabledLayouts = { SystemKeyboardLayouts.enabledLayoutIDs() }
        loadProfiles()
    }

    /// Isolated instance (tests, previews): nothing is read from or written to UserDefaults.
    init(profile: ConversionProfile, enabledLayouts: @escaping () -> [String] = { SystemKeyboardLayouts.enabledLayoutIDs() }) {
        self.defaults = nil
        self.enabledLayouts = enabledLayouts
        if profile.isEditable {
            customProfiles = [profile]
        }
        activeProfileID = profile.id
    }

    // MARK: - Profiles

    var activeProfile: ConversionProfile {
        profile(withID: activeProfileID) ?? .auto
    }

    func profile(withID id: String) -> ConversionProfile? {
        customProfiles.first { $0.id == id } ?? ConversionProfile.builtIn(id: id)
    }

    /// Auto, then the user's enabled layouts, then the common macOS layouts (both Russian variants etc.).
    func builtInProfiles() -> [ConversionProfile] {
        let enabled = enabledLayouts()
        var seen: Set<String> = [SystemKeyboardLayouts.abcLayoutID, "com.apple.keylayout.US"]
        let targets = (enabled + SystemKeyboardLayouts.commonLayoutIDs).filter { id in
            guard !seen.contains(id), SystemKeyboardLayouts.keyTable(layoutID: id) != nil else { return false }
            seen.insert(id)
            return true
        }
        return [.auto] + targets.map { ConversionProfile.system(target: $0) }
    }

    /// Resolved tables for the active profile. Auto re-reads enabled layouts, so it follows system changes.
    func resolvedActiveProfile() -> ResolvedProfile? {
        let profile = activeProfile
        let enabled = profile.isAuto || profile.isEditable ? enabledLayouts() : []
        let key = profile.id + "|" + enabled.joined(separator: ",") + "|\(profile.mapping.count)"
        if let cache = resolvedCache, cache.key == key {
            return cache.value
        }
        let value = Self.resolve(profile, enabledLayouts: enabled)
        resolvedCache = (key, value)
        return value
    }

    func resolvedProfile(for profile: ConversionProfile) -> ResolvedProfile? {
        profile.id == activeProfileID ? resolvedActiveProfile() : Self.resolve(profile, enabledLayouts: enabledLayouts())
    }

    static func resolve(_ profile: ConversionProfile, enabledLayouts: [String]) -> ResolvedProfile? {
        if profile.isAuto {
            guard let pair = SystemKeyboardLayouts.enabledAutoPair(enabled: enabledLayouts),
                  let mapping = SystemKeyboardLayouts.mapping(from: pair.source, to: pair.target) else {
                return nil
            }
            return ResolvedProfile(forward: mapping, sourceLayoutID: pair.source, targetLayoutID: pair.target)
        }

        if let target = profile.targetLayoutID {
            let source = profile.sourceLayoutID ?? SystemKeyboardLayouts.abcLayoutID
            guard let mapping = SystemKeyboardLayouts.mapping(from: source, to: target) else { return nil }
            return ResolvedProfile(forward: mapping, sourceLayoutID: source, targetLayoutID: target)
        }

        guard !profile.mapping.isEmpty else { return nil }
        let layouts = Self.guessLayouts(for: profile.mapping, enabled: enabledLayouts)
        return ResolvedProfile(forward: profile.mapping, sourceLayoutID: layouts.source, targetLayoutID: layouts.target)
    }

    /// For a custom table, find the enabled layouts that type its two sides (by the first differing letter key).
    private static func guessLayouts(for mapping: [String: String], enabled: [String]) -> (source: String?, target: String?) {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for (index, letter) in letters.enumerated() {
            let key = String(letter)
            guard let converted = mapping[key], converted != key else { continue }
            let keyCode = SystemKeyboardLayouts.letterKeyCodes[index]
            return (
                SystemKeyboardLayouts.enabledLayoutID(typing: key, atKeyCode: keyCode, enabled: enabled),
                SystemKeyboardLayouts.enabledLayoutID(typing: converted, atKeyCode: keyCode, enabled: enabled)
            )
        }
        return (nil, nil)
    }

    /// Enabled layout that types the side the text now ends on. Built-in profiles name ABC as the source,
    /// so users on US (or any other latin layout) get their own latin layout instead.
    func layoutIDToSelect(after direction: Direction) -> String? {
        guard let resolved = resolvedActiveProfile() else { return nil }
        return Self.layoutIDToSelect(after: direction, resolved: resolved, enabled: enabledLayouts())
    }

    static func layoutIDToSelect(after direction: Direction, resolved: ResolvedProfile, enabled: [String]) -> String? {
        let wanted = direction == .toTarget ? resolved.targetLayoutID : resolved.sourceLayoutID
        if let wanted, enabled.contains(wanted) {
            return wanted
        }
        if direction == .toSource {
            return enabled.first(where: SystemKeyboardLayouts.isLatin(layoutID:))
        }
        return guessLayouts(for: resolved.forward, enabled: enabled).target
    }

    // MARK: - Conversion

    func transformText(_ text: String, typedInLayoutID: String? = nil) -> String {
        convert(text, typedInLayoutID: typedInLayoutID).text
    }

    /// - Parameter typedInLayoutID: the layout active while the text was typed; breaks ties for
    ///   text with no layout-specific characters (e.g. a lone `?`).
    func convert(_ text: String, typedInLayoutID: String? = nil) -> Conversion {
        guard let resolved = resolvedActiveProfile() else {
            return Conversion(text: text, endsOn: nil)
        }
        let fallback: Direction
        if let typedInLayoutID, typedInLayoutID == resolved.targetLayoutID {
            fallback = .toSource
        } else if let typedInLayoutID, typedInLayoutID == resolved.sourceLayoutID || SystemKeyboardLayouts.isLatin(layoutID: typedInLayoutID) {
            fallback = .toTarget
        } else {
            fallback = .toSource
        }
        return Self.convert(text, using: resolved, fallback: fallback)
    }

    private enum Side {
        case source, target, both, none
    }

    private struct Token {
        let text: String
        let side: Side
        let isWhitespace: Bool
    }

    /// Splits text into mapping keys, longest match first, on Unicode scalars: combining marks
    /// (Arabic harakat, Hebrew points) and multi-scalar key outputs stay separate keys instead of
    /// being glued to the previous letter as one `Character`.
    private static func tokenize(_ scalars: [Unicode.Scalar], profile: ResolvedProfile) -> [Token] {
        var tokens: [Token] = []
        tokens.reserveCapacity(scalars.count)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.properties.isWhitespace {
                tokens.append(Token(text: String(scalar), side: .none, isWhitespace: true))
                index += 1
                continue
            }
            var token = Token(text: String(scalar), side: .none, isWhitespace: false)
            var consumed = 1
            for length in stride(from: min(profile.maxKeyLength, scalars.count - index), through: 1, by: -1) {
                var key = ""
                key.unicodeScalars.append(contentsOf: scalars[index..<(index + length)])
                let side: Side
                switch (profile.forward[key] != nil, profile.inverse[key] != nil) {
                case (true, true): side = .both
                case (true, false): side = .source
                case (false, true): side = .target
                case (false, false): continue
                }
                token = Token(text: key, side: side, isWhitespace: false)
                consumed = length
                break
            }
            tokens.append(token)
            index += consumed
        }
        return tokens
    }

    static func convert(_ text: String, using profile: ResolvedProfile, fallback: Direction = .toSource) -> Conversion {
        // NFC so a decomposed "й" (и + breve, common in macOS file names) is one key.
        let normalized = text.precomposedStringWithCanonicalMapping
        let tokens = tokenize(Array(normalized.unicodeScalars), profile: profile)
        guard !tokens.isEmpty else { return Conversion(text: text, endsOn: nil) }

        // Words are whitespace-separated runs; each gets a direction from its one-sided keys.
        var words: [Range<Int>] = []
        var start: Int?
        for index in tokens.indices {
            if tokens[index].isWhitespace {
                if let wordStart = start { words.append(wordStart..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let wordStart = start { words.append(wordStart..<tokens.count) }

        var directions: [Direction?] = words.map { range in
            var score = 0
            for index in range {
                switch tokens[index].side {
                case .source: score += 1
                case .target: score -= 1
                default: break
                }
            }
            return score > 0 ? .toTarget : score < 0 ? .toSource : nil
        }

        // Undecided words borrow from the previous decided word, then the next one, then the fallback.
        var previous: Direction?
        for index in directions.indices {
            if let direction = directions[index] { previous = direction } else { directions[index] = previous }
        }
        var next: Direction?
        for index in directions.indices.reversed() {
            if let direction = directions[index] { next = direction } else { directions[index] = next ?? fallback }
        }

        var output = ""
        output.reserveCapacity(normalized.utf8.count)
        var endsOn: Direction?
        var tokenIndex = 0
        for (wordIndex, range) in words.enumerated() {
            while tokenIndex < range.lowerBound {
                output += tokens[tokenIndex].text
                tokenIndex += 1
            }
            let direction = directions[wordIndex]
            for index in range {
                let token = tokens[index]
                let converted: String?
                switch token.side {
                case .source: converted = profile.forward[token.text]
                case .target: converted = profile.inverse[token.text]
                case .both: converted = direction == .toTarget ? profile.forward[token.text] : profile.inverse[token.text]
                case .none: converted = nil
                }
                if let converted, converted != token.text {
                    endsOn = direction
                }
                output += converted ?? token.text
            }
            tokenIndex = range.upperBound
        }
        while tokenIndex < tokens.count {
            output += tokens[tokenIndex].text
            tokenIndex += 1
        }

        // Nothing converted: hand back the caller's exact text, not its NFC form.
        guard endsOn != nil else { return Conversion(text: text, endsOn: nil) }
        return Conversion(text: output, endsOn: endsOn)
    }

    /// `target → source`. When two keys type the same character, the lexicographically smaller key wins,
    /// which prefers ASCII keys over the ISO `§`/`±` key.
    static func inverseMapping(of mapping: [String: String]) -> [String: String] {
        var inverse: [String: String] = [:]
        for from in mapping.keys.sorted() {
            guard let to = mapping[from], inverse[to] == nil else { continue }
            inverse[to] = from
        }
        return inverse
    }

    // MARK: - Persistence

    func loadProfiles() {
        guard let defaults else { return }
        if let data = defaults.data(forKey: DefaultsKeys.userProfiles),
           let decoded = try? JSONDecoder().decode([LossyProfile].self, from: data) {
            customProfiles = decoded.compactMap(\.profile).filter(\.isEditable)
        }
        migrateLegacyCustomSymbols()

        let storedID = defaults.string(forKey: DefaultsKeys.activeProfileID) ?? ConversionProfile.autoID
        activeProfileID = profile(withID: storedID) != nil ? storedID : ConversionProfile.autoID
        resolvedCache = nil
    }

    func saveProfiles() {
        guard let defaults, let data = try? JSONEncoder().encode(customProfiles) else { return }
        defaults.set(data, forKey: DefaultsKeys.userProfiles)
    }

    private func migrateLegacyCustomSymbols() {
        guard let defaults,
              let data = defaults.data(forKey: DefaultsKeys.customSymbols),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        customProfiles.append(.custom(name: "Migrated Custom Profile", mapping: mapping))
        defaults.removeObject(forKey: DefaultsKeys.customSymbols)
        saveProfiles()
    }

    /// Decodes one stored profile, skipping legacy built-ins instead of failing the whole array.
    private struct LossyProfile: Decodable {
        let profile: ConversionProfile?
        init(from decoder: Decoder) throws {
            profile = try? ConversionProfile(from: decoder)
        }
    }

    // MARK: - Custom profile editing

    /// Creates an editable copy of `template` (built-in tables are copied from the system layouts).
    @discardableResult
    func duplicateProfile(_ template: ConversionProfile) -> ConversionProfile {
        let mapping = self.mapping(of: template)
        let copy = ConversionProfile.custom(name: uniqueName("\(template.name) (copy)"), mapping: mapping)
        customProfiles.append(copy)
        saveProfiles()
        return copy
    }

    /// Saves a profile made in the editor; its name is made unique.
    @discardableResult
    func addCustomProfile(_ draft: ConversionProfile) -> ConversionProfile {
        var profile = draft
        profile.name = uniqueName(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "My Custom Profile" : draft.name)
        customProfiles.append(profile)
        saveProfiles()
        return profile
    }

    /// The key table of any profile, for showing or as a starting point for a custom one.
    func mapping(of profile: ConversionProfile) -> [String: String] {
        profile.isEditable ? profile.mapping : (resolvedProfile(for: profile)?.forward ?? [:])
    }

    @discardableResult
    func createEmptyProfile() -> ConversionProfile {
        let profile = ConversionProfile.custom(name: uniqueName("My Custom Profile"), mapping: [:])
        customProfiles.append(profile)
        saveProfiles()
        return profile
    }

    func updateProfile(_ profile: ConversionProfile) {
        guard profile.isEditable, let index = customProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        customProfiles[index] = profile
        resolvedCache = nil
        saveProfiles()
    }

    func deleteProfile(id: String) {
        customProfiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = ConversionProfile.autoID
        }
        saveProfiles()
    }

    private func uniqueName(_ base: String) -> String {
        var name = base
        var counter = 2
        while customProfiles.contains(where: { $0.name == name }) {
            name = "\(base) \(counter)"
            counter += 1
        }
        return name
    }
}
