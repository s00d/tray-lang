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
    private var isInitialized = false
    private var coordinator: AppCoordinator!
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isInitialized else { return }
        isInitialized = true
        
        // Инициализируем координатор
        coordinator = AppCoordinator()
        
        // Скрываем иконку в доке сразу при запуске
        coordinator.hideDockIcon()
        
        // Настраиваем UI
        setupStatusItem()
        
        // Запускаем приложение
        coordinator.start()
    }
    
    func setupStatusItem() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tray Lang")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        setupPopover()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 250, height: 300)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: TrayMenuView(coordinator: coordinator)
        )
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        
        // Принудительно скрываем иконку в доке
        coordinator.hideDockIcon()
        
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.contentViewController = NSHostingController(
                rootView: TrayMenuView(coordinator: coordinator)
            )
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator.accessibilityManager.updateAccessibilityStatus()
        // Принудительно скрываем иконку в доке при активации
        coordinator.hideDockIcon()
    }
}
