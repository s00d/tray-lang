import SwiftUI
import AppKit

// MARK: - NSImage Extension
extension NSImage {
    func withTintColor(_ color: NSColor) -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return self
        }
        
        return NSImage(size: size, flipped: false) { bounds in
            color.setFill()
            bounds.fill()
            
            let imageRect = NSRect(origin: .zero, size: self.size)
            self.draw(in: imageRect, from: imageRect, operation: .destinationIn, fraction: 1.0)
            
            return true
        }
    }
}

// MARK: - Window Manager
@MainActor
class WindowManager: NSObject, ObservableObject, NSMenuDelegate {
    private var mainWindow: NSWindow?
    private var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?
    
    // Ссылки на пункты меню, которые нужно будет обновлять
    private var autoLaunchMenuItem: NSMenuItem?
    private var smartLayoutMenuItem: NSMenuItem?
    
    override init() {
        super.init()
    }
    
    func setCoordinator(_ coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - Status Bar Setup
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tray Lang")
            button.imagePosition = .imageLeft
            
            // Создаем наше нативное меню
            let menu = NSMenu()
            menu.delegate = self // Для динамического обновления
            
            // Добавляем пункты меню
            let openSettingsItem = menu.addItem(withTitle: "Open Settings", action: #selector(showMainWindow), keyEquivalent: "")
            openSettingsItem.target = self
            menu.addItem(.separator())
            
            // Динамические пункты (с галочками)
            autoLaunchMenuItem = menu.addItem(withTitle: "Auto Launch", action: #selector(toggleAutoLaunch), keyEquivalent: "")
            autoLaunchMenuItem?.target = self
            smartLayoutMenuItem = menu.addItem(withTitle: "Smart Layout", action: #selector(toggleSmartLayout), keyEquivalent: "")
            smartLayoutMenuItem?.target = self
            
            menu.addItem(.separator())
            
            let aboutItem = menu.addItem(withTitle: "About...", action: #selector(showAboutWindow), keyEquivalent: "")
            aboutItem.target = self
            let quitItem = menu.addItem(withTitle: "Quit Tray Lang", action: #selector(quitApp), keyEquivalent: "q")
            quitItem.target = self
            
            // Привязываем меню к иконке
            statusItem?.menu = menu
        }
    }
    
    func updateStatusItemTitle(shortName: String) {
        // ИСПРАВЛЕНО: Гарантируем выполнение в main thread
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.title = shortName
        }
    }
    
    // НОВОЕ: Обновление иконки статус-бара в зависимости от состояния
    func updateStatusItemIcon(isSecureInputActive: Bool = false, isEnabled: Bool = true) {
        // ИСПРАВЛЕНО: Гарантируем выполнение в main thread
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem?.button else { return }
            
            if isSecureInputActive {
                // Secure Input активен - показываем замок (желтый)
                button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Input Active")
                button.image?.isTemplate = false
                // Окрашиваем в желтый
                let yellowImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Input Active")
                yellowImage?.isTemplate = false
                let coloredImage = yellowImage?.withTintColor(.systemYellow)
                button.image = coloredImage
            } else if !isEnabled {
                // Отключено - показываем перечеркнутую клавиатуру (серый)
                button.image = NSImage(systemSymbolName: "keyboard.slash", accessibilityDescription: "Tray Lang Disabled")
                button.image?.isTemplate = true
            } else {
                // Нормальный режим - обычная клавиатура
                button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tray Lang")
                button.image?.isTemplate = true
            }
        }
    }
    
    // MARK: - NSMenuDelegate
    
    // Эта функция будет вызываться каждый раз перед открытием меню
    func menuNeedsUpdate(_ menu: NSMenu) {
        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Гарантируем выполнение в main thread!
        // NSMenu delegate может вызываться из любого потока
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let coordinator = self.coordinator else { return }
            
            // Обновляем состояние галочек
            self.autoLaunchMenuItem?.state = coordinator.autoLaunchManager.isAutoLaunchEnabled() ? .on : .off
            self.smartLayoutMenuItem?.state = coordinator.smartLayoutManager.isEnabled ? .on : .off
        }
    }
    
    // MARK: - Menu Actions
    
    @objc func showMainWindow() {
        // Принудительно показываем иконку в доке перед открытием окна
        showDockIcon()
        
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            createMainWindow()
        }
    }
    
    @objc func toggleAutoLaunch() {
        guard let coordinator = coordinator else { return }
        if coordinator.autoLaunchManager.isAutoLaunchEnabled() {
            coordinator.autoLaunchManager.disableAutoLaunch()
        } else {
            coordinator.autoLaunchManager.enableAutoLaunch()
        }
    }
    
    @objc func toggleSmartLayout() {
        guard let coordinator = coordinator else { return }
        Task { @MainActor in
            coordinator.smartLayoutManager.isEnabled.toggle()
        }
    }
    
    @objc func showAboutWindow() {
        // Открытие главного окна и отправка уведомления
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .showAboutWindow, object: nil)
        }
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Main Window Management
    
    private func createMainWindow() {
        guard let coordinator = coordinator else { return }
        let contentView = ContentView(coordinator: coordinator)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tray Lang"
        window.delegate = self
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        mainWindow = window
    }
    
    // MARK: - Dock Icon Management
    func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }
    
    // MARK: - Cleanup
    deinit {
        statusItem = nil
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
            // ИСПРАВЛЕНО: Очищаем contentView для разрыва retain cycles SwiftUI
            window.contentView = nil
            mainWindow = nil
            hideDockIcon()
            debugLog("🧹 WindowManager: Окно закрыто и очищено от retain cycles")
        }
    }
} 