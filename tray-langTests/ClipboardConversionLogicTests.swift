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

    @Test func mode3DoesNotStackTwoHalfSecondModifierWaits() {
        // Regression: old path waited 0.5s before Cmd+C and again inside performCmdC,
        // plus 0.5s for pasteboard — felt like 1–3s of "nothing happens".
        let stackedLegacyWaits = 0.5 + 0.5 + 0.5
        #expect(ClipboardConversionTiming.maxPassiveMode3Wait < stackedLegacyWaits * 0.5)
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
        #expect(ConversionAppRouting.usesTerminalPath(bundleID: "com.microsoft.VSCode"))
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

    @Test func promptStripIsOnlyForTerminalPathNotBrowserURLs() {
        // Browser/editor path must never call TerminalPromptExtractor.
        #expect(!ConversionAppRouting.usesTerminalPath(bundleID: "com.brave.Browser"))
        #expect(!ConversionAppRouting.usesTerminalPath(bundleID: "com.apple.Safari"))
    }
}

struct PasteboardHelperTests {
    @Test func waitReturnsQuicklyWhenPasteboardChanges() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("tray-lang.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)
        let original = pasteboard.changeCount

        let started = Date()
        // Change on a background queue while the wait pumps the run loop
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.015) {
            pasteboard.clearContents()
            pasteboard.setString("after", forType: .string)
        }

        let changed = PasteboardHelper.waitForPasteboardChange(
            originalCount: original,
            timeout: 0.25,
            pasteboard: pasteboard
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(changed)
        #expect(elapsed < 0.2)
        #expect(pasteboard.string(forType: .string) == "after")
    }

    @Test func waitTimesOutWhenPasteboardUnchanged() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("tray-lang.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("stable", forType: .string)
        let original = pasteboard.changeCount
        let started = Date()

        let changed = PasteboardHelper.waitForPasteboardChange(
            originalCount: original,
            timeout: 0.05,
            pasteboard: pasteboard
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(!changed)
        #expect(elapsed >= 0.04)
        #expect(elapsed < 0.35)
    }
}
