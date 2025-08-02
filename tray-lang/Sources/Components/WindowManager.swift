import SwiftUI
import AppKit

// MARK: - Window Manager
class WindowManager: NSObject, ObservableObject {
    private var mainWindow: NSWindow?
    private var coordinator: AppCoordinator?
    
    override init() {
        super.init()
    }
    
    func setCoordinator(_ coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - Main Window Management
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFront(nil)
        } else {
            createMainWindow()
        }
        
        // Иконка в доке остается скрытой
    }
    
    private func createMainWindow() {
        guard let coordinator = coordinator else { return }
        let contentView = ContentView(coordinator: coordinator)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tray Lang"
        window.delegate = self
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFront(nil)
        
        mainWindow = window
    }
    
    // MARK: - Dock Icon Management
    func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }
}

// MARK: - NSWindowDelegate
extension WindowManager: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        hideDockIcon()
        return false
    }
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == mainWindow {
            mainWindow = nil
            hideDockIcon()
        }
    }
} 