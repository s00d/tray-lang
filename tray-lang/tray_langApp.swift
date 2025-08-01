//
//  tray_langApp.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit
import ApplicationServices

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
    lazy var trayLangManager: TrayLangManager = {
        let manager = TrayLangManager()
        return manager
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Создание иконки в трее
        setupStatusItem()
        
        // Настройка автозапуска
        setupAutoLaunch()
        
        // Проверяем права доступа и перезапускаем при необходимости
        checkAccessibilityPermissions()
    }
    
    func setupStatusItem() {
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
        
        // Устанавливаем делегат для главного окна
        if let window = NSApp.windows.first {
            window.delegate = self
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                // Обновляем contentViewController каждый раз при открытии
                popover?.contentViewController = NSHostingController(
                    rootView: TrayMenuView(trayLangManager: trayLangManager, showMainWindow: showMainWindow)
                )
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    func setupAutoLaunch() {
        let isAutoLaunchEnabled = UserDefaults.standard.bool(forKey: "autoLaunchEnabled")
        
        if isAutoLaunchEnabled {
            trayLangManager.enableAutoLaunch()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Не закрываем приложение при закрытии окна, а сворачиваем в трей
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Останавливаем мониторинг горячих клавиш при выходе
        trayLangManager.stopMonitoring()
    }
    
    func hideMainWindow() {
        // Приложение запускается без окон, поэтому ничего не скрываем
        print("✅ Приложение запущено в скрытом режиме")
    }
    
    func checkAccessibilityPermissions() {
        // Проверяем права доступа к Accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessibilityEnabled {
            // Если права не предоставлены, показываем уведомление
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showAccessibilityAlert()
            }
        }
    }
    
    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "Tray Lang needs accessibility permissions to work properly. Please grant permissions in System Preferences and restart the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Restart App")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Открываем System Preferences
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case .alertSecondButtonReturn:
            // Перезапускаем приложение
            restartApp()
        default:
            break
        }
    }
    
    func restartApp() {
        // Перезапускаем приложение
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", Bundle.main.bundlePath]
        task.launch()
        
        // Завершаем текущий процесс
        NSApp.terminate(nil)
    }
    
    func showMainWindow() {
        print("🔍 showMainWindow вызвана")
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = mainWindow {
            print("✅ Найдено существующее окно, показываем его")
            window.makeKeyAndOrderFront(nil)
        } else {
            print("❌ Окно не найдено, создаем новое")
            // Если окно не существует, создаем новое
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
            
            // Сохраняем ссылку на окно
            mainWindow = window
            print("✅ Новое окно создано и сохранено")
        }
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("🔍 windowShouldClose вызвана для окна: \(sender.title)")
        // Скрываем окно вместо закрытия, но сохраняем ссылку на него
        sender.orderOut(nil)
        print("✅ Окно скрыто, ссылка сохранена")
        return false
    }
    
    func windowWillClose(_ notification: Notification) {
        print("🔍 windowWillClose вызвана")
        // Очищаем ссылку на окно только при реальном закрытии
        if let window = notification.object as? NSWindow, window == mainWindow {
            print("❌ Очищаем ссылку на главное окно")
            mainWindow = nil
        }
    }
}
