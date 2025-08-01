//
//  tray_langApp.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

@main
struct tray_langApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var mainWindow: NSWindow?
    var isInitialized = false
    lazy var trayLangManager: TrayLangManager = {
        let manager = TrayLangManager()
        return manager
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isInitialized else { return }
        isInitialized = true
        
        print("🚀 Приложение запущено")
        setupStatusItem()
        hideDockIcon() // Скрываем иконку в доке при запуске
    }
    
    func setupStatusItem() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tray Lang")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 250, height: 300)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: TrayMenuView(trayLangManager: trayLangManager, showMainWindow: showMainWindow)
        )
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.contentViewController = NSHostingController(
                    rootView: TrayMenuView(trayLangManager: trayLangManager, showMainWindow: showMainWindow)
                )
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        trayLangManager.stopMonitoring()
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Проверяем права доступа при активации приложения
        trayLangManager.updateAccessibilityStatus()
    }
    
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFront(nil)
        } else {
            let contentView = ContentView()
                .environmentObject(trayLangManager)
            
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
        
        // Показываем иконку в доке
        showDockIcon()
    }
    
    func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
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
