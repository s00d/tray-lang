import Foundation
import AppKit
import Testing
@testable import tray_lang

struct ClipboardConversionLogicTests {
    @Test func mode3PassiveWaitBudgetStaysUnderCeiling() {
        #expect(ClipboardConversionTiming.modifiersTimeout <= 0.25)
        #expect(ClipboardConversionTiming.pasteboardChangeTimeout <= 0.3)
        #expect(ClipboardConversionTiming.clipboardRestoreDelay <= 0.3)
        #expect(
            ClipboardConversionTiming.maxPassiveMode3Wait
                <= ClipboardConversionTiming.maxAllowedPassiveMode3Wait
        )
    }

    @Test func markerCaptureRejectsEmptyAndMarkerItself() {
        let marker = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        #expect(ClipboardMarkerLogic.capturedText(marker: marker, pasteboardString: nil) == nil)
        #expect(ClipboardMarkerLogic.capturedText(marker: marker, pasteboardString: "") == nil)
        #expect(ClipboardMarkerLogic.capturedText(marker: marker, pasteboardString: marker) == nil)
    }

    @Test func markerCaptureAcceptsSelectedText() {
        let marker = "MARKER"
        #expect(
            ClipboardMarkerLogic.capturedText(marker: marker, pasteboardString: "hello world")
                == "hello world"
        )
    }

    @Test func skipRestoreWhenPasteboardChangedExternally() {
        #expect(ClipboardMarkerLogic.shouldSkipRestore(currentChangeCount: 10, writtenChangeCount: 9))
        #expect(!ClipboardMarkerLogic.shouldSkipRestore(currentChangeCount: 9, writtenChangeCount: 9))
    }
}

struct HoldDurationLogicTests {
    @Test func holdUsesSecondsNotKeyRepeatCounts() {
        let started = Date(timeIntervalSince1970: 1000)
        #expect(
            !HoldDurationLogic.hasHeldLongEnough(
                startedAt: started,
                now: started.addingTimeInterval(0.9),
                requiredSeconds: 1
            )
        )
        #expect(
            HoldDurationLogic.hasHeldLongEnough(
                startedAt: started,
                now: started.addingTimeInterval(1.0),
                requiredSeconds: 1
            )
        )
        #expect(
            HoldDurationLogic.hasHeldLongEnough(
                startedAt: started,
                now: started.addingTimeInterval(3.0),
                requiredSeconds: 3
            )
        )
    }

    @Test func autorepeatDoesNotStartNewHold() {
        #expect(HoldDurationLogic.shouldBeginHold(isAlreadyHolding: false, isAutorepeat: false))
        #expect(!HoldDurationLogic.shouldBeginHold(isAlreadyHolding: false, isAutorepeat: true))
        #expect(!HoldDurationLogic.shouldBeginHold(isAlreadyHolding: true, isAutorepeat: false))
        #expect(!HoldDurationLogic.shouldBeginHold(isAlreadyHolding: true, isAutorepeat: true))
    }
}

struct ConversionAppRoutingTests {
    @Test func terminalsUseTerminalPath() {
        #expect(ConversionAppRouting.usesTerminalPath(bundleID: "com.apple.Terminal"))
        #expect(ConversionAppRouting.usesTerminalPath(bundleID: "com.googlecode.iterm2"))
    }

    @Test func browsersDoNotUseTerminalPath() {
        #expect(!ConversionAppRouting.usesTerminalPath(bundleID: "com.brave.Browser"))
        #expect(!ConversionAppRouting.usesTerminalPath(bundleID: "com.google.Chrome"))
        #expect(!ConversionAppRouting.usesTerminalPath(bundleID: "com.apple.Safari"))
    }
}

struct TerminalPromptExtractorTests {
    @Test func stripsCommonShellPrompts() {
        #expect(TerminalPromptExtractor.extractCommand(from: "$ git status") == "git status")
        #expect(TerminalPromptExtractor.extractCommand(from: "% ls -la") == "ls -la")
        #expect(TerminalPromptExtractor.extractCommand(from: "> echo hi") == "echo hi")
        #expect(TerminalPromptExtractor.extractCommand(from: "➜ npm test") == "npm test")
    }

    @Test func stripsRightSidePromptNoise() {
        let line = "git push    [main] 12:30"
        let command = TerminalPromptExtractor.extractCommand(from: line)
        #expect(command.hasPrefix("git push"))
        #expect(!command.contains("12:30"))
    }

    @Test func keepsWholeLineWhenThereIsNoPrompt() {
        #expect(TerminalPromptExtractor.extractCommand(from: "ghbdtn") == "ghbdtn")
    }
}

struct PasteboardHelperTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("tray-lang.tests.\(UUID().uuidString)"))
    }

    /// The copying app as the waiting code sees it: each poll returns the next scripted state,
    /// so no threads or timing are involved.
    final class ScriptedPasteboard: PasteboardReading {
        private let states: [(count: Int, text: String?)]
        private var polls = 0

        init(_ states: [(count: Int, text: String?)]) {
            self.states = states
        }

        private var current: (count: Int, text: String?) {
            states[min(polls, states.count - 1)]
        }

        var changeCount: Int {
            defer { polls += 1 }
            return current.count
        }

        func string(forType type: NSPasteboard.PasteboardType) -> String? {
            current.text
        }
    }

    @Test func returnsTheNewStringOnceItIsWritten() {
        let pasteboard = ScriptedPasteboard([(1, "before"), (1, "before"), (2, "after")])
        #expect(PasteboardHelper.waitForString(changedFrom: 1, timeout: 2, pasteboard: pasteboard) == "after")
    }

    /// clearContents() bumps changeCount before the copy lands; reading right then returned nil and lost the selection.
    @Test func waitsPastClearContentsForTheString() {
        let pasteboard = ScriptedPasteboard([(1, "before"), (2, nil), (2, nil), (2, nil), (3, "copied")])
        #expect(PasteboardHelper.waitForString(changedFrom: 1, timeout: 2, pasteboard: pasteboard) == "copied")
    }

    @Test func givesUpWhenTheCopyNeverLands() {
        let pasteboard = ScriptedPasteboard([(1, "before"), (2, nil)])
        #expect(PasteboardHelper.waitForString(changedFrom: 1, timeout: 0.05, pasteboard: pasteboard) == nil)
    }

    @Test func realPasteboardIsReadImmediatelyWhenAlreadyChanged() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)
        let original = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("now", forType: .string)
        #expect(PasteboardHelper.waitForString(changedFrom: original, timeout: 1, pasteboard: pasteboard) == "now")
    }

    @Test func timesOutWhenNothingChanges() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("stable", forType: .string)
        let started = Date()
        #expect(PasteboardHelper.waitForString(changedFrom: pasteboard.changeCount, timeout: 0.05, pasteboard: pasteboard) == nil)
        #expect(Date().timeIntervalSince(started) >= 0.05)
    }

    @Test func backupRestoresEveryType() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("text", forType: .string)
        item.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.binary"))
        pasteboard.writeObjects([item])

        let backup = ClipboardBackup(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        backup.restore()

        #expect(pasteboard.string(forType: .string) == "text")
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("com.example.binary")) == Data([1, 2, 3]))
    }

    @Test func emptyBackupRestoresAnEmptyClipboard() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let backup = ClipboardBackup(pasteboard)
        pasteboard.setString("temporary", forType: .string)
        backup.restore()
        #expect(pasteboard.string(forType: .string) == nil)
    }
}
