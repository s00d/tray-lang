import Foundation
import AppKit

// MARK: - HUD view

/// System-style HUD: blurred rounded panel, SF Symbol, one line of text, optional hold progress.
final class HUDAlertView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        iconView.symbolConfiguration = .init(pointSize: 34, weight: .regular)
        iconView.contentTintColor = .labelColor

        textLabel.font = .systemFont(ofSize: 14, weight: .medium)
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byTruncatingTail

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small

        let stack = NSStackView(views: [iconView, textLabel, progress])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            progress.widthAnchor.constraint(equalToConstant: 180),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var currentText: String { textLabel.stringValue }

    func update(text: String, symbol: String) {
        textLabel.stringValue = text
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    /// Fills the bar over `duration` with one Core Animation pass instead of a 20 Hz timer.
    func startProgress(duration: TimeInterval) {
        progress.isHidden = false
        progress.doubleValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            progress.animator().doubleValue = 1
        }
    }

    func hideProgress() {
        progress.isHidden = true
        progress.doubleValue = 0
    }
}

// MARK: - HUD window

/// Never becomes key, so showing it does not steal focus from the app being edited.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HUDAlertManager {
    static let shared = HUDAlertManager()

    private static let size = NSSize(width: 300, height: 130)
    private let window: HUDPanel
    private let hudView: HUDAlertView
    private var dismissWork: DispatchWorkItem?
    private(set) var isVisible = false

    private init() {
        window = HUDPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.identifier = NSUserInterfaceItemIdentifier("tray-lang.hud")

        hudView = HUDAlertView(frame: NSRect(origin: .zero, size: Self.size))
        window.contentView = hudView
    }

    var currentText: String? { isVisible ? hudView.currentText : nil }

    /// - Parameter duration: when set, shows a progress bar and hides itself after that time.
    func show(text: String, symbol: String, duration: TimeInterval? = nil) {
        dismissWork?.cancel()
        hudView.update(text: text, symbol: symbol)
        isVisible = true

        if let duration {
            hudView.startProgress(duration: duration)
            let work = DispatchWorkItem { [weak self] in self?.dismiss() }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        } else {
            hudView.hideProgress()
        }

        // Screen with the mouse — that's where the user is looking; visibleFrame origin matters on secondary screens.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        window.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.midY - Self.size.height / 2))
        window.alphaValue = 1
        // Paint now: conversion runs synchronously on main right after this.
        window.orderFrontRegardless()
        window.displayIfNeeded()
    }

    func dismiss(animated: Bool = true) {
        dismissWork?.cancel()
        dismissWork = nil
        guard isVisible else { return }
        isVisible = false
        guard animated else {
            window.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.window.orderOut(nil)
        })
    }
}

// MARK: - Notification manager

final class NotificationManager {
    var isHUDVisible: Bool { HUDAlertManager.shared.isVisible }
    var hudText: String? { HUDAlertManager.shared.currentText }

    func showHUD(text: String, symbol: String, duration: TimeInterval? = nil) {
        HUDAlertManager.shared.show(text: text, symbol: symbol, duration: duration)
    }

    func dismissHUD(animated: Bool = true) {
        HUDAlertManager.shared.dismiss(animated: animated)
    }
}
