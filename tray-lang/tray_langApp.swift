//
//  tray_langApp.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit
import Combine

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
    private var coordinator: AppCoordinator!
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Инициализируем координатор
        coordinator = AppCoordinator()
        
        // Делегируем всю работу с UI WindowManager'у
        coordinator.windowManager.setCoordinator(coordinator)
        coordinator.windowManager.setupStatusBar()
        
        // Подписываемся на смену раскладки для обновления иконки
        coordinator.keyboardLayoutManager.$currentLayout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLayout in
                self?.coordinator.windowManager.updateStatusItemTitle(shortName: newLayout?.shortName ?? "")
            }
            .store(in: &cancellables)
        
        // Запускаем приложение
        coordinator.start()
        
        // Этот трюк работает, давая системе завершить цикл запуска,
        // после чего мы устанавливаем финальное состояние иконки.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.coordinator.hideDockIcon()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Используем `?` для безопасного вызова
        coordinator?.stop()
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("Получен запрос на завершение работы...")
        // Выполняем все необходимые действия по очистке до того, как приложение закроется
        coordinator?.stop()
        // Сообщаем системе, что мы готовы к завершению
        return .terminateNow
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator?.accessibilityManager.updateAccessibilityStatus()
        // Убрали hideDockIcon() отсюда - иконка управляется только через WindowManager
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Приложение продолжает работать в трее
    }
}
