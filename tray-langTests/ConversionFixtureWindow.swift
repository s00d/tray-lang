import AppKit

/// In-process fixture window for conversion / HUD integration tests.
@MainActor
final class ConversionFixtureWindow {
    enum Mode {
        case textField
        case textView
        /// Reserved — AX selected-text is unreliable; tests should XCTSkip.
        case webView
    }

    private(set) var window: NSWindow
    private let mode: Mode
    private var textField: NSTextField?
    private var textView: NSTextView?

    var isWebViewMode: Bool { mode == .webView }

    var currentText: String {
        switch mode {
        case .textField:
            return textField?.stringValue ?? ""
        case .textView:
            return textView?.string ?? ""
        case .webView:
            return ""
        }
    }

    init(mode: Mode = .textField) {
        self.mode = mode

        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 480, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tray Lang Conversion Fixture"
        window.identifier = NSUserInterfaceItemIdentifier("tray-lang.fixture.window")
        window.setFrameAutosaveName("")
        self.window = window

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        window.contentView = content

        switch mode {
        case .textField:
            let field = NSTextField(frame: NSRect(x: 20, y: 100, width: 440, height: 28))
            field.identifier = NSUserInterfaceItemIdentifier("tray-lang.fixture.field")
            field.setAccessibilityIdentifier("tray-lang.fixture.field")
            field.isEditable = true
            field.isSelectable = true
            field.font = .systemFont(ofSize: 16)
            content.addSubview(field)
            textField = field

        case .textView:
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 440, height: 180))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let view = NSTextView(frame: scroll.bounds)
            view.isEditable = true
            view.isSelectable = true
            view.font = .systemFont(ofSize: 16)
            view.setAccessibilityIdentifier("tray-lang.fixture.field")
            scroll.documentView = view
            content.addSubview(scroll)
            textView = view

        case .webView:
            let label = NSTextField(labelWithString: "WebView fixture reserved — XCTSkip in tests")
            label.frame = NSRect(x: 20, y: 100, width: 440, height: 24)
            label.setAccessibilityIdentifier("tray-lang.fixture.webview")
            content.addSubview(label)
        }
    }

    func show(withText text: String) {
        switch mode {
        case .textField:
            textField?.stringValue = text
        case .textView:
            textView?.string = text
        case .webView:
            break
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        switch mode {
        case .textField:
            window.makeFirstResponder(textField)
        case .textView:
            window.makeFirstResponder(textView)
        case .webView:
            break
        }

        pumpRunLoop(for: 0.05)
    }

    func selectAll() {
        switch mode {
        case .textField:
            textField?.selectText(nil)
            textField?.currentEditor()?.selectAll(nil)
        case .textView:
            textView?.selectAll(nil)
        case .webView:
            break
        }
        pumpRunLoop(for: 0.05)
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        textField = nil
        textView = nil
    }

    func pumpRunLoop(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}
