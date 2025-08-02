import Foundation
import AppKit

// MARK: - Notification Manager
class NotificationManager: ObservableObject {
    private var notificationWindow: NSWindow?
    
    // MARK: - Conversion Notification
    func showConversionNotification() {
        DispatchQueue.main.async {
            if self.notificationWindow == nil {
                self.createNotificationWindow()
            }
            
            guard let window = self.notificationWindow else { return }
            
            window.alphaValue = 1.0
            window.orderFront(nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                window.orderOut(nil)
            }
        }
    }
    
    private func createNotificationWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.4).cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        
        let label = NSTextField(labelWithString: "🔄 Converting layout...")
        label.textColor = NSColor.white
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 20, width: 240, height: 20)
        
        containerView.addSubview(label)
        window.contentView = containerView
        
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowFrame = window.frame
            let x = (screenFrame.width - windowFrame.width) / 2
            let y = (screenFrame.height - windowFrame.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.notificationWindow = window
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