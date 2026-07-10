import Foundation
import AppKit

class SpellCheckManager: ObservableObject {
    private let checker = NSSpellChecker.shared

    init() {
        checker.automaticallyIdentifiesLanguages = true
    }

    /// Исправляет орфографические ошибки, выбирая лучший вариант.
    func fixText(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let nsString = text as NSString
        var resultText = text
        var replacements: [(NSRange, String)] = []

        var offset = 0
        while offset < nsString.length {
            let misspelledRange = checker.checkSpelling(
                of: text,
                startingAt: offset
            )

            if misspelledRange.location == NSNotFound {
                break
            }

            let guesses = checker.guesses(
                forWordRange: misspelledRange,
                in: text,
                language: nil,
                inSpellDocumentWithTag: 0
            )

            if let bestGuess = guesses?.first {
                let originalWord = nsString.substring(with: misspelledRange)
                let matchedGuess = matchCapitalization(original: originalWord, guess: bestGuess)
                replacements.append((misspelledRange, matchedGuess))
            }

            offset = misspelledRange.location + misspelledRange.length
        }

        for (range, replacement) in replacements.reversed() {
            guard let swiftRange = Range(range, in: resultText) else { continue }
            resultText.replaceSubrange(swiftRange, with: replacement)
        }

        return resultText
    }

    private func matchCapitalization(original: String, guess: String) -> String {
        guard let firstChar = original.first else { return guess }

        if firstChar.isUppercase {
            if original.uppercased() == original {
                return guess.uppercased()
            }
            return guess.prefix(1).uppercased() + guess.dropFirst().lowercased()
        }

        return guess.lowercased()
    }
}
