//
//  SmartLayoutManager.swift
//  tray-lang
//
//  Created by s00d on 14.11.2025.
//

import Foundation
import AppKit

// Структура для удобного отображения в SwiftUI
struct RememberedLayout: Identifiable, Hashable {
    var id: String { appBundleID } // Используем bundleID как уникальный идентификатор
    var appBundleID: String
    var appName: String
    var layoutID: String
    var layoutName: String
    
    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

class SmartLayoutManager: ObservableObject {
    // @Published позволит UI автоматически обновляться при изменении этого значения
    @Published var isEnabled: Bool {
        didSet {
            // Сохраняем любое изменение в UserDefaults для персистентности
            UserDefaults.standard.set(isEnabled, forKey: "smartLayoutEnabled")
            // Включаем или выключаем мониторинг в зависимости от состояния
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    // Новое свойство для правил
    @Published var defaultRules: [AppLayoutRule] = [] {
        didSet {
            saveRules()
            updatePublishedRememberedLayouts() // Обновляем UI при изменении правил
        }
    }
    
    // Новое @Published свойство для UI
    @Published var publishedRememberedLayouts: [RememberedLayout] = []
    
    private let keyboardLayoutManager: KeyboardLayoutManager
    private var rememberedLayouts: [String: String] = [:] // Переименовали для ясности
    
    // Ключи для UserDefaults
    private let rulesUserDefaultsKey = "smartLayoutRules"
    private let rememberedUserDefaultsKey = "rememberedAppLayouts"
    
    init(keyboardLayoutManager: KeyboardLayoutManager) {
        self.keyboardLayoutManager = keyboardLayoutManager
        
        // Читаем сохраненное значение. Если его нет, по умолчанию будет `false`
        self.isEnabled = UserDefaults.standard.bool(forKey: "smartLayoutEnabled")
        
        loadRules()
        loadRememberedLayouts() // Этот метод теперь будет вызывать обновление UI
        
        // Запускаем мониторинг только если функция была включена ранее
        if isEnabled {
            startMonitoring()
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func startMonitoring() {
        print("🧠 Smart Layout Manager: Started monitoring.")
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appDidDeactivate), name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appDidActivate), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    private func stopMonitoring() {
        print("🧠 Smart Layout Manager: Stopped monitoring.")
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func appDidDeactivate(notification: Notification) {
        // Эта функция срабатывает, когда приложение перестает быть активным
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              let currentLayout = keyboardLayoutManager.currentLayout else { return }
        
        // Запоминаем раскладку, только если нет правила
        if !defaultRules.contains(where: { $0.appBundleID == bundleID }) {
            rememberedLayouts[bundleID] = currentLayout.id
            saveRememberedLayouts()
            updatePublishedRememberedLayouts() // Обновляем UI
            print("🧠 Saved layout '\(currentLayout.localizedName)' for \(bundleID)")
        }
    }
    
    @objc private func appDidActivate(notification: Notification) {
        // Эта функция срабатывает, когда приложение становится активным
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        // Новая логика приоритетов
        
        // ПРИОРИТЕТ 1: Проверяем правила по умолчанию
        if let rule = defaultRules.first(where: { $0.appBundleID == bundleID }) {
            if rule.layoutID != keyboardLayoutManager.currentLayout?.id {
                keyboardLayoutManager.switchToLayout(id: rule.layoutID)
                print("🧠 Applied default rule for \(bundleID): switch to \(rule.layoutID)")
            }
            return // Правило применено, выходим
        }
        
        // ПРИОРИТЕТ 2: Проверяем запомненные раскладки
        if let rememberedLayoutID = rememberedLayouts[bundleID] {
            if rememberedLayoutID != keyboardLayoutManager.currentLayout?.id {
                keyboardLayoutManager.switchToLayout(id: rememberedLayoutID)
                print("🧠 Switched to remembered layout for \(bundleID): \(rememberedLayoutID)")
            }
        }
    }
    
    // --- Управление правилами ---
    func addRule(for app: NSRunningApplication, layoutID: String) {
        guard let bundleID = app.bundleIdentifier, let appName = app.localizedName else { return }
        
        // Удаляем старое правило, если оно было
        removeRule(for: bundleID)
        
        let newRule = AppLayoutRule(appBundleID: bundleID, appName: appName, layoutID: layoutID)
        defaultRules.append(newRule)
    }
    
    func removeRule(for bundleID: String) {
        defaultRules.removeAll { $0.appBundleID == bundleID }
        updatePublishedRememberedLayouts() // Обновляем UI, так как приложение может появиться в запомненных
    }
    
    // НОВЫЙ МЕТОД для "закрепления"
    func promoteToRule(remembered: RememberedLayout) {
        // Создаем новое правило из запомненного
        let newRule = AppLayoutRule(appBundleID: remembered.appBundleID, appName: remembered.appName, layoutID: remembered.layoutID)
        
        // Удаляем старое правило для этого приложения, если оно было
        defaultRules.removeAll { $0.appBundleID == newRule.appBundleID }
        // Добавляем новое
        defaultRules.append(newRule)
        
        // Удаляем из запомненных, так как теперь есть постоянное правило
        rememberedLayouts.removeValue(forKey: remembered.appBundleID)
        saveRememberedLayouts()
        updatePublishedRememberedLayouts()
    }
    
    // --- Persistence ---
    private func saveRules() {
        if let data = try? JSONEncoder().encode(defaultRules) {
            UserDefaults.standard.set(data, forKey: rulesUserDefaultsKey)
        }
    }
    
    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesUserDefaultsKey),
           let saved = try? JSONDecoder().decode([AppLayoutRule].self, from: data) {
            defaultRules = saved
        }
    }
    
    private func saveRememberedLayouts() {
        UserDefaults.standard.set(rememberedLayouts, forKey: rememberedUserDefaultsKey)
    }
    
    private func loadRememberedLayouts() {
        rememberedLayouts = UserDefaults.standard.dictionary(forKey: rememberedUserDefaultsKey) as? [String: String] ?? [:]
        updatePublishedRememberedLayouts() // Обновляем UI при загрузке
    }
    
    // НОВЫЙ МЕТОД для конвертации словаря в массив для UI
    private func updatePublishedRememberedLayouts() {
        var newPublished: [RememberedLayout] = []
        for (bundleID, layoutID) in rememberedLayouts {
            // Игнорируем, если для этого приложения уже есть правило по умолчанию
            if defaultRules.contains(where: { $0.appBundleID == bundleID }) {
                continue
            }
            
            let appName = NSWorkspace.shared.applicationName(for: bundleID)
            let layoutName = keyboardLayoutManager.availableLayouts.first { $0.id == layoutID }?.localizedName ?? "Unknown"
            
            newPublished.append(RememberedLayout(appBundleID: bundleID, appName: appName, layoutID: layoutID, layoutName: layoutName))
        }
        
        // Сортируем для стабильного отображения
        self.publishedRememberedLayouts = newPublished.sorted { $0.appName < $1.appName }
    }
}

// Добавьте это расширение в конец файла для удобства
extension NSWorkspace {
    func applicationName(for bundleIdentifier: String) -> String {
        if let url = self.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: url) {
            return bundle.localizedInfoDictionary?["CFBundleName"] as? String ?? bundle.infoDictionary?["CFBundleName"] as? String ?? bundleIdentifier
        }
        return bundleIdentifier
    }
}
