import Foundation
import AppKit

/// Fixes misspelled words with the system spell checker.
/// The language is picked per word from its script: automatic detection misses short Russian text
/// (`привт` is detected as Bulgarian and never flagged).
final class SpellCheckManager {
    private let checker = NSSpellChecker.shared

    func fixText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var replacements: [(Range<String.Index>, String)] = []

        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, range, _, _ in
            guard let word, let replacement = self.correction(for: word), replacement != word else { return }
            replacements.append((range, replacement))
        }

        var result = text
        for (range, replacement) in replacements.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    func correction(for word: String) -> String? {
        let language = Self.language(for: word, available: checker.availableLanguages)
        let range = NSRange(location: 0, length: (word as NSString).length)

        // Autocorrect's pick first (what macOS itself would type), then the first suggestion.
        if let correction = checker.correction(forWordRange: range, in: word, language: language ?? "", inSpellDocumentWithTag: 0) {
            return Self.matchCapitalization(original: word, guess: correction)
        }
        var wordCount = 0
        let misspelled = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: &wordCount)
        guard misspelled.location != NSNotFound,
              let guess = checker.guesses(forWordRange: misspelled, in: word, language: language, inSpellDocumentWithTag: 0)?.first else {
            return nil
        }
        return Self.matchCapitalization(original: word, guess: guess)
    }

    /// Cyrillic → Ukrainian if it has і/ї/є/ґ, else Russian; Latin → English. Nil lets the checker decide.
    static func language(for word: String, available: [String]) -> String? {
        func pick(_ candidates: [String]) -> String? {
            candidates.first { candidate in available.contains(candidate) }
        }
        let scalars = word.unicodeScalars
        if scalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
            if word.lowercased().contains(where: { "іїєґ".contains($0) }), let ukrainian = pick(["uk"]) {
                return ukrainian
            }
            if word.lowercased().contains("ў"), let belarusian = pick(["be"]) {
                return belarusian
            }
            return pick(["ru", "uk", "bg", "be"])
        }
        if scalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }) {
            return pick(["en", "en_US", "en_GB"])
        }
        return nil
    }

    static func matchCapitalization(original: String, guess: String) -> String {
        guard let first = original.first, first.isUppercase else { return guess }
        if original.count > 1, original.uppercased() == original {
            return guess.uppercased()
        }
        return guess.prefix(1).uppercased() + guess.dropFirst()
    }
}
