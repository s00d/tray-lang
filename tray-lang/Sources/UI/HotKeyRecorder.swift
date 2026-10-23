import SwiftUI
import AppKit

/// Click, press a shortcut, done. Esc cancels. Global hotkeys are paused while recording
/// so the current shortcut can be typed again.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Type shortcut…" : hotKey.displayString)
                .monospacedDigit()
                .frame(minWidth: 110)
        }
        .help(isRecording ? "Press a shortcut with ⌘, ⌥ or ⌃. Esc cancels." : "Click to record a new shortcut")
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53, flags.isDisjoint(with: [.command, .option, .control, .shift]) {
                stop()
                return nil
            }
            guard let captured = HotKey(keyCode: Int(event.keyCode), flags: flags) else {
                NSSound.beep()
                return nil
            }
            hotKey = captured
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}
