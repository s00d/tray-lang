import AppKit
import AudioToolbox

/// Says whether a word exists in its language.
protocol WordValidator {
    func isWord(_ word: String) -> Bool
}

/// System dictionaries; the language is picked from the word's script (see `SpellCheckManager.language`).
struct SpellCheckWordValidator: WordValidator {
    func isWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        guard let language = SpellCheckManager.language(for: word, available: checker.availableLanguages) else { return false }
        var wordCount = 0
        let misspelled = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: &wordCount)
        return misspelled.location == NSNotFound && wordCount > 0
    }
}

/// Decides, key by key, when a just-typed word should be retyped in the other layout.
/// Pure state machine: no events are read or posted here.
struct AutoConvertEngine {
    struct Key: Equatable {
        var keyCode: UInt16
        var characters: String
        var hasCommandOrControl = false
        /// Posted by this app (marked with `KeystrokeOutput.marker`).
        var isSynthetic = false
    }

    enum Action: Equatable {
        case none
        /// Delete `deleteCount` characters before the caret, type `text`, then select the layout of `switchTo`.
        case replace(deleteCount: Int, text: String, switchTo: TextTransformer.Direction)
        case undo(deleteCount: Int, text: String, switchTo: TextTransformer.Direction)

        var isUndo: Bool {
            if case .undo = self { return true }
            return false
        }
    }

    private struct LastConversion {
        let original: String
        let converted: String
        let direction: TextTransformer.Direction
    }

    private static let spaceKey: UInt16 = 49
    private static let deleteKey: UInt16 = 51
    /// Return, Enter, Tab, Esc, Forward Delete, Home, End, Page Up/Down, arrows.
    private static let resetKeys: Set<UInt16> = [36, 76, 48, 53, 117, 115, 119, 116, 121, 123, 124, 125, 126]
    static let minimumLetters = 2

    private let transformer: TextTransformer
    private let validator: WordValidator
    private var word = ""
    private var lastConversion: LastConversion?
    /// Words the user undid in this session: never touched again.
    private var ignored: Set<String> = []

    init(transformer: TextTransformer, validator: WordValidator) {
        self.transformer = transformer
        self.validator = validator
    }

    mutating func reset() {
        word = ""
        lastConversion = nil
    }

    /// `currentLayoutID` is evaluated only when a word is checked (on Space).
    mutating func handle(_ key: Key, currentLayoutID: @autoclosure () -> String?) -> Action {
        if key.isSynthetic { return .none }
        if key.hasCommandOrControl || Self.resetKeys.contains(key.keyCode) {
            reset()
            return .none
        }

        switch key.keyCode {
        case Self.deleteKey:
            if let last = lastConversion {
                // The user's Delete already removed the space after the converted word.
                lastConversion = nil
                ignored.insert(last.original)
                return .undo(
                    deleteCount: last.converted.count,
                    text: last.original + " ",
                    switchTo: last.direction == .toTarget ? .toSource : .toTarget
                )
            }
            if !word.isEmpty { word.removeLast() }
            return .none

        case Self.spaceKey:
            let typed = word
            word = ""
            lastConversion = nil
            guard let (converted, direction) = conversion(of: typed, layoutID: currentLayoutID()) else { return .none }
            lastConversion = LastConversion(original: typed, converted: converted, direction: direction)
            return .replace(deleteCount: typed.count + 1, text: converted + " ", switchTo: direction)

        default:
            lastConversion = nil
            guard !key.characters.isEmpty,
                  key.characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
                reset()
                return .none
            }
            word += key.characters
            return .none
        }
    }

    /// Converted text when `word` is not a word but its conversion is, across scripts only.
    private func conversion(of word: String, layoutID: String?) -> (String, TextTransformer.Direction)? {
        let letters = word.filter(\.isLetter)
        guard letters.count >= Self.minimumLetters,
              !ignored.contains(word),
              !word.contains(where: { $0.isNumber || "@/_\\:".contains($0) }) else { return nil }

        let result = transformer.convert(word, typedInLayoutID: layoutID)
        guard let direction = result.endsOn, result.text != word else { return nil }

        // Latin ↔ Latin pairs (QWERTY/QWERTZ…) produce real words both ways; only flip between scripts.
        let convertedLetters = result.text.filter(\.isLetter)
        let wasLatin = letters.allSatisfy(\.isASCII)
        let isLatin = convertedLetters.allSatisfy(\.isASCII)
        guard wasLatin != isLatin, !convertedLetters.isEmpty,
              letters.allSatisfy({ $0.isASCII == wasLatin }) else { return nil }

        guard !validator.isWord(word), validator.isWord(result.text) else { return nil }
        return (result.text, direction)
    }
}

/// Types text into the frontmost app with synthetic key events, independent of the keyboard layout.
struct KeystrokeOutput {
    /// Stamped into `eventSourceUserData` so our own events are recognised and ignored.
    static let marker: Int64 = 0x7472_796C

    /// Unicode events carry at most 20 UTF-16 units; never split a surrogate pair.
    static func chunks(_ text: String, limit: Int = 20) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for unit in text.utf16 {
            if current.count >= limit || (current.count == limit - 1 && UTF16.isLeadSurrogate(unit)) {
                chunks.append(current)
                current = []
            }
            current.append(unit)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    func deleteBackward(_ count: Int) {
        for _ in 0..<count {
            post(keyCode: 51, text: nil)
        }
    }

    func type(_ text: String) {
        for chunk in Self.chunks(text) {
            post(keyCode: 0, text: chunk)
        }
    }

    private let source = CGEventSource(stateID: .privateState)

    private func post(keyCode: CGKeyCode, text: [UniChar]?) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = []
            if var text {
                event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: &text)
            }
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cghidEventTap)
        }
    }
}

/// Watches typing while enabled and retypes words that came out in the wrong layout.
/// Nothing is installed while it is off; while on, each key costs a string append.
final class AutoConvertManager {
    var isEnabled = false { didSet { updateMonitoring() } }
    /// Key events can only be observed with Accessibility access.
    var canMonitor = false { didSet { updateMonitoring() } }
    var playsSound = true
    var skipsTerminalsAndCodeEditors = true

    private let transformer: TextTransformer
    private let keyboardLayoutManager: KeyboardLayoutManager
    private let output: KeystrokeOutput
    private var engine: AutoConvertEngine
    private var monitors: [Any] = []
    /// Updated on app activation, so a keystroke never asks NSWorkspace.
    private var frontmostIsSkipped = false
    /// Key-downs we just posted, in case an app strips the marker: they are skipped, for at most half a second.
    private var expectedSynthetic = (count: 0, until: Date.distantPast)
    private var activationObserver: NSObjectProtocol?
    /// 75 ms sine glide, up for "fixed", down for "undone"; loaded once, played by the system sound server.
    private lazy var fixedSound = Self.loadSound("switch")
    private lazy var undoneSound = Self.loadSound("switch-back")

    private static func loadSound(_ name: String) -> SystemSoundID? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        var id: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError ? id : nil
    }

    private static let codeEditors: Set<String> = [
        "com.apple.dt.Xcode", "com.panic.Nova", "com.barebones.bbedit", "org.vim.MacVim", "com.github.atom",
    ]

    static func isSkippedByDefault(bundleID: String) -> Bool {
        ConversionAppRouting.usesTerminalPath(bundleID: bundleID)
            || ConversionAppRouting.copiesWholeLineWithoutSelection(bundleID: bundleID)
            || codeEditors.contains(bundleID)
    }

    var isMonitoring: Bool { !monitors.isEmpty }

    init(
        transformer: TextTransformer,
        keyboardLayoutManager: KeyboardLayoutManager,
        validator: WordValidator = SpellCheckWordValidator(),
        output: KeystrokeOutput = KeystrokeOutput()
    ) {
        self.transformer = transformer
        self.keyboardLayoutManager = keyboardLayoutManager
        self.output = output
        engine = AutoConvertEngine(transformer: transformer, validator: validator)
    }

    deinit {
        stop()
    }

    private func updateMonitoring() {
        let shouldRun = isEnabled && canMonitor && !ProcessRuntime.isRunningUnderTests
        if shouldRun, monitors.isEmpty {
            start()
        } else if !shouldRun, !monitors.isEmpty {
            stop()
        }
    }

    private func start() {
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(keys)
        }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.engine.reset() }) {
            monitors.append(clicks)
        }
        frontmostIsSkipped = Self.isSkippedByDefault(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostIsSkipped = Self.isSkippedByDefault(bundleID: app?.bundleIdentifier ?? "")
            self?.engine.reset()
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        engine.reset()
    }

    private func handle(_ event: NSEvent) {
        if skipsTerminalsAndCodeEditors, frontmostIsSkipped {
            engine.reset()
            return
        }
        var isSynthetic = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == KeystrokeOutput.marker
        if expectedSynthetic.count > 0, Date() < expectedSynthetic.until {
            expectedSynthetic.count -= 1
            isSynthetic = true
        }
        let key = AutoConvertEngine.Key(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            hasCommandOrControl: !event.modifierFlags.isDisjoint(with: [.command, .control]),
            isSynthetic: isSynthetic
        )
        perform(engine.handle(key, currentLayoutID: keyboardLayoutManager.currentLayoutID))
    }

    private func perform(_ action: AutoConvertEngine.Action) {
        switch action {
        case .none:
            return
        case let .replace(deleteCount, text, direction), let .undo(deleteCount, text, direction):
            expectedSynthetic = (deleteCount + KeystrokeOutput.chunks(text).count, Date().addingTimeInterval(0.5))
            output.deleteBackward(deleteCount)
            output.type(text)
            if let layoutID = transformer.layoutIDToSelect(after: direction) {
                keyboardLayoutManager.switchToLayout(id: layoutID)
            }
            if playsSound, let sound = action.isUndo ? undoneSound : fixedSound {
                AudioServicesPlaySystemSound(sound)
            }
        }
    }
}
