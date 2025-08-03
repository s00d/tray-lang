import Foundation
import AppKit

// MARK: - HUD Alert View
class HUDAlertView: NSView {
    private let containerView = NSView()
    private let textLabel = NSTextField()
    private let iconLabel = NSTextField()
    private let progressView = NSView()
    private let progressBar = NSView()
    private var progressTimer: Timer?
    private var totalDuration: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.masksToBounds = true
        
        // Add subtle border
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        
        // Add shadow
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowOffset = CGSize(width: 0, height: 4)
        layer?.shadowRadius = 8

        // Container view for better layout
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(containerView)

        // Icon label with larger size
        iconLabel.stringValue = "🔒"
        iconLabel.textColor = NSColor.white
        iconLabel.font = NSFont.systemFont(ofSize: 32, weight: .medium)
        iconLabel.alignment = .center
        iconLabel.isEditable = false
        iconLabel.isBordered = false
        iconLabel.backgroundColor = NSColor.clear
        iconLabel.frame = NSRect(x: 0, y: 50, width: 300, height: 40)
        containerView.addSubview(iconLabel)

        // Text label with better styling
        textLabel.stringValue = "Hold Cmd+Q to quit"
        textLabel.textColor = NSColor.white
        textLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        textLabel.alignment = .center
        textLabel.isEditable = false
        textLabel.isBordered = false
        textLabel.backgroundColor = NSColor.clear
        textLabel.frame = NSRect(x: 0, y: 10, width: 300, height: 30)
        containerView.addSubview(textLabel)
        
        // Progress background
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        progressView.layer?.cornerRadius = 2
        progressView.frame = NSRect(x: 50, y: 5, width: 200, height: 4)
        containerView.addSubview(progressView)
        
        // Progress bar (fills from right to left)
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.white.cgColor
        progressBar.layer?.cornerRadius = 2
        progressBar.frame = NSRect(x: 50, y: 5, width: 200, height: 4)
        containerView.addSubview(progressBar)
    }

    func updateText(_ text: String, icon: String = "🔒") {
        textLabel.stringValue = text
        iconLabel.stringValue = icon
    }
    
    func startProgress(duration: TimeInterval) {
        totalDuration = duration
        elapsedTime = 0
        
        // Reset progress bar to full width
        progressBar.frame = NSRect(x: 50, y: 5, width: 200, height: 4)
        
        // Start timer
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        elapsedTime += 0.05
        
        let progress = elapsedTime / totalDuration
        let remainingWidth = 200 * (1 - progress)
        
        // Animate progress bar shrinking from right to left
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.05
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            progressBar.animator().frame = NSRect(x: 50, y: 5, width: remainingWidth, height: 4)
        })
        
        if progress >= 1.0 {
            progressTimer?.invalidate()
            progressTimer = nil
        }
    }
    
    func stopProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    override func layout() {
        super.layout()
        
        // Center container view
        containerView.frame = NSRect(
            x: (bounds.width - 300) / 2,
            y: (bounds.height - 90) / 2,
            width: 300,
            height: 90
        )
    }
}

// MARK: - HUD Alert Manager
class HUDAlertManager {
    static let shared = HUDAlertManager()

    private var window: NSWindow
    private var delayer: DispatchWorkItem?

    private init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false  // We handle shadow in the view
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hudView = HUDAlertView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        window.contentView = hudView
    }

    func showHUD(text: String, icon: String = "🔒", delayTime: TimeInterval? = nil) {
        guard let screenRect = NSScreen.main?.visibleFrame else {
            print("Could not get screen frame")
            return
        }

        // Cancel previous delay if exists
        delayer?.cancel()

        // Update HUD content
        if let hudView = window.contentView as? HUDAlertView {
            hudView.updateText(text, icon: icon)
            
            // Start progress bar if delay is specified
            if let delayTime = delayTime {
                hudView.startProgress(duration: delayTime)
            }
        }

        // Position window in center
        let newRect = NSRect(
            x: (screenRect.size.width - 320) * 0.5,
            y: (screenRect.size.height - 120) * 0.5,
            width: 320,
            height: 120
        )
        window.setFrame(newRect, display: true)

        // Show window with fade in animation
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 1.0
        })

        // Auto-dismiss after delay if specified
        if let delayTime = delayTime {
            delayer = DispatchWorkItem {
                self.dismissHUD()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delayTime, execute: delayer!)
        }
    }

    func dismissHUD(fade: Bool = true) {
        delayer?.cancel()

        // Stop progress bar
        if let hudView = window.contentView as? HUDAlertView {
            hudView.stopProgress()
        }

        guard fade else {
            window.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }) {
            self.window.orderOut(nil)
        }
    }
}

// MARK: - Notification Manager
class NotificationManager: ObservableObject {
    private var notificationWindow: NSWindow?

    // MARK: - Conversion Notification
    func showConversionNotification() {
        showHUD(text: "Converting layout...", icon: "🔄", delayTime: 0.5)
    }

    // MARK: - HUD Notifications
    func showHUD(text: String, icon: String = "ℹ️", delayTime: TimeInterval? = nil) {
        HUDAlertManager.shared.showHUD(text: text, icon: icon, delayTime: delayTime)
    }

    func dismissHUD() {
        HUDAlertManager.shared.dismissHUD()
    }

    // MARK: - Legacy QBlocker HUD (for backward compatibility)
    func showQBlockerHUD(delaySeconds: Int) {
        showHUD(
            text: "Hold Cmd+Q for \(delaySeconds) seconds to quit",
            icon: "🔒",
            delayTime: TimeInterval(delaySeconds)
        )
    }

    func dismissQBlockerHUD() {
        dismissHUD()
    }

    // MARK: - Alert Dialogs
    func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func showConfirmationAlert(title: String, message: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn)
        }
    }
}
