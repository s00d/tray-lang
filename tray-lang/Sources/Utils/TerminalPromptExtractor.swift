import Foundation

enum TerminalPromptExtractor {
    /// Strip shell prompts from the last terminal line before converting the command.
    /// Must NOT be used for browser/editor text (URLs with `$` / `#` would break).
    static func extractCommand(from line: String) -> String {
        var clean = line.trimmingCharacters(in: .whitespacesAndNewlines)

        let prompts = ["$ ", "% ", "> ", "# ", "ζ ", ": ", "➜ ", "❯ ", "$", "%", ">", "#", "ζ"]
        for prompt in prompts {
            if let range = clean.range(of: prompt, options: .backwards) {
                clean = String(clean[range.upperBound...])
                break
            }
        }

        let rightPromptPattern = "\\s{2,}(\\[.*?\\]|\\(.*?\\)|<.*?>|\\d{2}:\\d{2}(:\\d{2})?|[✔✘]).*?$"
        if let range = clean.range(of: rightPromptPattern, options: .regularExpression) {
            clean.removeSubrange(range)
        }

        let result = clean.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? line.trimmingCharacters(in: .whitespaces) : result
    }
}

enum ConversionAppRouting {
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "co.zeit.hyper",
        "org.alacritty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
        "com.googlecode.iterm2-nightly",
    ]

    static func usesTerminalPath(bundleID: String) -> Bool {
        terminalBundleIDs.contains(bundleID)
    }
}
