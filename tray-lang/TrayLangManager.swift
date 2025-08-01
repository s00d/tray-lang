import Foundation
import AppKit
import Carbon
import ApplicationServices
import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - Key Information Structure
struct KeyInfo {
    let keyCode: Int
    let name: String
    let displayName: String
}

// MARK: - Accessibility Status
enum AccessibilityStatus {
    case unknown
    case granted
    case denied
    case requesting
    
    var description: String {
        switch self {
        case .unknown:
            return "Статус неизвестен"
        case .granted:
            return "Разрешения предоставлены"
        case .denied:
            return "Разрешения не предоставлены"
        case .requesting:
            return "Запрос разрешений..."
        }
    }
    
    var color: Color {
        switch self {
        case .unknown:
            return .orange
        case .granted:
            return .green
        case .denied:
            return .red
        case .requesting:
            return .blue
        }
    }
}

// MARK: - Available Keys
extension TrayLangManager {
    private static var cachedKeyCodes: [KeyInfo]?
    private static var lastCacheTime: Date = Date.distantPast
    private static let cacheTimeout: TimeInterval = 5.0 // 5 секунд
    
    // Кэш для названий раскладок
    private static var cachedLayoutName: String?
    private static var lastLayoutCheck: Date = Date.distantPast
    private static let layoutCacheTimeout: TimeInterval = 2.0 // 2 секунды
    
    // Кэш для анализа раскладок
    private static var cachedLayoutAnalysis: [String: [KeyInfo]] = [:]
    private static var lastAnalysisCheck: Date = Date.distantPast
    private static let analysisCacheTimeout: TimeInterval = 3.0 // 3 секунды
    
    static func getAvailableKeyCodes() -> [KeyInfo] {
        // Проверяем кэш
        let now = Date()
        if let cached = cachedKeyCodes, 
           now.timeIntervalSince(lastCacheTime) < cacheTimeout {
            return cached
        }
        
        var keyInfos: [KeyInfo] = []
        
        // 1. Получаем клавиши из системы через Carbon API
        if let systemKeys = getSystemKeyCodes() {
            keyInfos.append(contentsOf: systemKeys)
            print("✅ Получено \(systemKeys.count) клавиш из системных API")
        }
        
        // 2. Если системные API не вернули клавиши, используем fallback
        if keyInfos.isEmpty {
            keyInfos = getFallbackKeyCodes()
            print("⚠️ Использованы fallback клавиши")
        }
        
        // Сортируем по keyCode для удобства
        let sortedKeys = keyInfos.sorted { $0.keyCode < $1.keyCode }
        print("📊 Всего доступно клавиш: \(sortedKeys.count)")
        
        // Кэшируем результат
        cachedKeyCodes = sortedKeys
        lastCacheTime = now
        
        return sortedKeys
    }
    
    // Метод для принудительного обновления кэша
    static func refreshAvailableKeyCodes() {
        cachedKeyCodes = nil
        lastCacheTime = Date.distantPast
    }
    
    private static func getSystemKeyCodes() -> [KeyInfo]? {
        var keyInfos: [KeyInfo] = []
        
        // Получаем текущую раскладку клавиатуры
        guard let keyboardLayout = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            print("❌ Не удалось получить текущую раскладку клавиатуры")
            return nil
        }
        
        // Получаем информацию о раскладке (кэшируем)
        let now = Date()
        let layoutName: String
        
        if let cached = cachedLayoutName, 
           now.timeIntervalSince(lastLayoutCheck) < layoutCacheTimeout {
            layoutName = cached
        } else {
            if let namePtr = TISGetInputSourceProperty(keyboardLayout, kTISPropertyLocalizedName) {
                layoutName = Unmanaged<CFString>.fromOpaque(namePtr).takeRetainedValue() as String
                cachedLayoutName = layoutName
                lastLayoutCheck = now
                print("🔍 Обнаружена раскладка: \(layoutName)")
            } else {
                layoutName = "Unknown"
            }
        }
        
        // Получаем информацию о клавишах для текущей раскладки
        if let keyCodeMap = getKeyCodeMapForLayout(keyboardLayout) {
            keyInfos.append(contentsOf: keyCodeMap)
        }
        
        return keyInfos.isEmpty ? nil : keyInfos
    }
    
    private static func getKeyCodeMapForLayout(_ layout: TISInputSource) -> [KeyInfo]? {
        var keyInfos: [KeyInfo] = []
        
        // Получаем информацию о раскладке клавиатуры (кэшируем)
        let now = Date()
        let layoutName: String
        
        if let namePtr = TISGetInputSourceProperty(layout, kTISPropertyLocalizedName) {
            layoutName = Unmanaged<CFString>.fromOpaque(namePtr).takeRetainedValue() as String
        } else {
            return nil
        }
        
        // Проверяем кэш анализа раскладки
        if let cached = cachedLayoutAnalysis[layoutName],
           now.timeIntervalSince(lastAnalysisCheck) < analysisCacheTimeout {
            return cached
        }
        
        print("🔍 Анализируем раскладку: \(layoutName)")
        
        // Для разных раскладок получаем разные клавиши
        if layoutName.contains("Russian") || layoutName.contains("Русский") {
            // Русская раскладка
            keyInfos.append(contentsOf: getRussianLayoutKeys())
        } else if layoutName.contains("English") || layoutName.contains("US") {
            // Английская раскладка
            keyInfos.append(contentsOf: getEnglishLayoutKeys())
        } else {
            // Другие раскладки
            keyInfos.append(contentsOf: getGenericLayoutKeys())
        }
        
        // Кэшируем результат анализа
        cachedLayoutAnalysis[layoutName] = keyInfos
        lastAnalysisCheck = now
        
        return keyInfos.isEmpty ? nil : keyInfos
    }
    
    private static func getAdditionalKeysFromSystem(_ layout: TISInputSource) -> [KeyInfo]? {
        // Упрощенная версия - пока не используем сложные Carbon API
        // В будущем здесь можно добавить получение клавиш через UCKeyTranslate
        return nil
    }
    
    private static func getRussianLayoutKeys() -> [KeyInfo] {
        var keys: [KeyInfo] = []
        
        // Получаем русские клавиши из системы
        // Используем системные API для получения реальных keyCode
        
        // Буквы (получаем из системы)
        let russianLetters = ["А", "Б", "В", "Г", "Д", "Е", "Ё", "Ж", "З", "И", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ъ", "Ы", "Ь", "Э", "Ю", "Я"]
        
        // Цифры и символы
        let russianSymbols = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/"]
        
        // Получаем keyCode для каждой клавиши из системы
        for letter in russianLetters {
            let keyCode = getSystemKeyCode(for: letter)
            if keyCode != -1 {
                keys.append(KeyInfo(keyCode: keyCode, name: letter, displayName: letter))
            }
        }
        
        for symbol in russianSymbols {
            let keyCode = getSystemKeyCode(for: symbol)
            if keyCode != -1 {
                keys.append(KeyInfo(keyCode: keyCode, name: symbol, displayName: symbol))
            }
        }
        
        return keys
    }
    
    private static func getEnglishLayoutKeys() -> [KeyInfo] {
        var keys: [KeyInfo] = []
        
        // Получаем английские клавиши из системы
        let englishLetters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        
        let englishSymbols = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/"]
        
        // Получаем keyCode для каждой клавиши из системы
        for letter in englishLetters {
            let keyCode = getSystemKeyCode(for: letter)
            if keyCode != -1 {
                keys.append(KeyInfo(keyCode: keyCode, name: letter, displayName: letter))
            }
        }
        
        for symbol in englishSymbols {
            let keyCode = getSystemKeyCode(for: symbol)
            if keyCode != -1 {
                keys.append(KeyInfo(keyCode: keyCode, name: symbol, displayName: symbol))
            }
        }
        
        return keys
    }
    
    private static func getGenericLayoutKeys() -> [KeyInfo] {
        var keys: [KeyInfo] = []
        
        // Универсальные клавиши, которые есть во всех раскладках
        let universalKeys = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        
        for key in universalKeys {
            let keyCode = getSystemKeyCode(for: key)
            if keyCode != -1 {
                keys.append(KeyInfo(keyCode: keyCode, name: key, displayName: key))
            }
        }
        
        return keys
    }
    
    private static func getSystemKeyCode(for character: String) -> Int {
        // Упрощенная версия - используем базовое соответствие
        // В реальности здесь должна быть логика получения keyCode из системы
        return getFallbackKeyCode(for: character)
    }
    
    private static func getFallbackKeyCode(for character: String) -> Int {
        // Базовое соответствие для случаев, когда системные API не работают
        let keyCodeMap: [String: Int] = [
            // Буквы
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
            "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
            "Y": 17, "T": 16, "U": 32, "I": 34, "O": 31, "P": 35,
            "L": 37, "J": 38, "K": 40, "N": 45, "M": 46,
            
            // Цифры
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 22, "6": 23, "7": 24, "8": 25, "9": 26, "0": 29,
            
            // Символы
            "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
            
            // Русские буквы (базовое соответствие)
            "А": 0, "Б": 11, "В": 9, "Г": 5, "Д": 2, "Е": 14, "Ё": 14, "Ж": 6, "З": 8, "И": 34,
            "Й": 34, "К": 40, "Л": 37, "М": 46, "Н": 45, "О": 31, "П": 35, "Р": 15, "С": 1, "Т": 16,
            "У": 32, "Ф": 3, "Х": 4, "Ц": 7, "Ч": 39, "Ш": 41, "Щ": 42, "Ъ": 43, "Ы": 44, "Ь": 47,
            "Э": 27, "Ю": 30, "Я": 33
        ]
        
        return keyCodeMap[character] ?? -1
    }
    
    private static func getFallbackKeyCodes() -> [KeyInfo] {
        // Fallback - базовые клавиши, если системные API не работают
        let basicKeys: [(Int, String, String)] = [
            (0, "A", "A"), (1, "S", "S"), (2, "D", "D"), (3, "F", "F"),
            (4, "H", "H"), (5, "G", "G"), (6, "Z", "Z"), (7, "X", "X"),
            (8, "C", "C"), (9, "V", "V"), (11, "B", "B"), (12, "Q", "Q"),
            (13, "W", "W"), (14, "E", "E"), (15, "R", "R"), (16, "T", "T"),
            (17, "Y", "Y"), (18, "1", "1"), (19, "2", "2"), (20, "3", "3"),
            (21, "4", "4"), (22, "5", "5"), (23, "6", "6"), (24, "7", "7"),
            (25, "8", "8"), (26, "9", "9"), (27, "0", "0")
        ]
        
        return basicKeys.map { KeyInfo(keyCode: $0.0, name: $0.1, displayName: $0.2) }
    }
    
    static func getAvailableModifiers() -> [(CGEventFlags, String)] {
        return [
            (.maskCommand, "⌘"),
            (.maskShift, "⇧"),
            (.maskAlternate, "⌥"),
            (.maskControl, "⌃")
        ]
    }
}

class TrayLangManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isEnabled: Bool = false
    @Published var currentLayout: String = "US"
    @Published var availableLayouts: [String] = []
    @Published var hotKey: HotKey = HotKey(keyCode: 18, modifiers: [.maskCommand]) // Command+1
    @Published var accessibilityStatus: AccessibilityStatus = .unknown
    
    // MARK: - Private Properties
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyCaptureEventTap: CFMachPort?
    private var keyCaptureRunLoopSource: CFRunLoopSource?
    @Published var fromToMapping: [String: String] = [
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p",
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l",
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P",
        "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K", "Д": "L",
        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M"
    ]
    private var toFromMapping: [String: String] = [:]
    
    // MARK: - Initialization
    init() {
        setupToFromMapping()
        loadAvailableLayouts()
        updateCurrentLayout()
        loadHotKey()
        updateAccessibilityStatus()
        requestAccessibilityPermissions()
        startMonitoring()
        
        // Таймер для обновления текущей раскладки
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateCurrentLayout()
        }
        
        // Таймер для обновления статуса доступности
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.updateAccessibilityStatus()
        }
        
        // Загружаем настраиваемые символы при старте
        loadSymbols()
    }
    
    // MARK: - Accessibility Permissions
    func requestAccessibilityPermissions() {
        accessibilityStatus = .requesting
        
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if !accessibilityEnabled {
            print("⚠️ Запрашиваем разрешения на доступность...")
            
            // Показываем диалог с инструкциями
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Разрешения на доступность"
                alert.informativeText = "Для работы горячих клавиш необходимо разрешить доступ к системе. Нажмите 'Открыть настройки' и добавьте это приложение в список разрешенных в разделе 'Доступность'."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Открыть настройки")
                alert.addButton(withTitle: "Отмена")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Открываем системные настройки
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                // Обновляем статус после диалога
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.updateAccessibilityStatus()
                }
            }
        } else {
            print("✅ Разрешения на доступность уже предоставлены")
            accessibilityStatus = .granted
        }
    }
    
    func updateAccessibilityStatus() {
        let accessibilityEnabled = AXIsProcessTrusted()
        let previousStatus = accessibilityStatus
        accessibilityStatus = accessibilityEnabled ? .granted : .denied
        
        // Если права только что получены, автоматически запускаем мониторинг
        if accessibilityEnabled && previousStatus != .granted {
            print("✅ Права получены! Автоматически запускаем мониторинг...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startMonitoring()
            }
        }
    }
    
    // MARK: - Setup Methods
    private func setupToFromMapping() {
        for (from, to) in fromToMapping {
            toFromMapping[to] = from
        }
    }
    
    // MARK: - Hot Key Management
    func startMonitoring() {
        guard eventTap == nil else { return }
        
        // Проверяем разрешения на доступность
        if !AXIsProcessTrusted() {
            print("❌ Нет разрешений на доступность")
            return
        }
        
        print("🔧 Запуск мониторинга горячих клавиш...")
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                
                let manager = Unmanaged<TrayLangManager>.fromOpaque(refcon).takeUnretainedValue()
                
                if manager.handleKeyEvent(event) {
                    // Если горячая клавиша сработала, не передаем событие дальше
                    return nil
                }
                
                // Передаем событие дальше
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            print("✅ Мониторинг горячих клавиш запущен")
        } else {
            print("❌ Не удалось создать event tap")
        }
    }
    
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
            print("🛑 Мониторинг горячих клавиш остановлен")
        }
    }
    

    
    private func handleKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        print("🔍 Клавиша: \(keyCode), Флаги: \(flags.rawValue)")
        print("🎯 Ожидаемая клавиша: \(hotKey.keyCode), Ожидаемые флаги: \(hotKey.modifiers.map { $0.rawValue })")
        
        // Проверяем модификаторы
        let hasCommand = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        
        print("🔧 Модификаторы: Command=\(hasCommand), Shift=\(hasShift), Option=\(hasOption), Control=\(hasControl)")
        
        // Проверяем, что все ожидаемые модификаторы присутствуют
        let allModifiersPresent = hotKey.modifiers.allSatisfy { modifier in
            flags.contains(modifier)
        }
        
        print("✅ Все модификаторы присутствуют: \(allModifiersPresent)")
        
        // Проверяем совпадение клавиши и модификаторов
        if keyCode == hotKey.keyCode && allModifiersPresent {
            print("🎯 Горячая клавиша сработала!")
            performLayoutSwitch()
            return true
        }
        
        return false
    }
    
    // MARK: - Key Capture
    func startKeyCapture() {
        guard keyCaptureEventTap == nil else { 
            print("⚠️ Захват уже запущен")
            return 
        }
        
        // Проверяем разрешения на доступность
        if !AXIsProcessTrusted() {
            print("❌ Нет разрешений на доступность для захвата клавиш")
            return
        }
        
        print("🔧 Запуск захвата клавиш...")
        
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        keyCaptureEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { 
                    print("❌ Нет refcon в callback захвата")
                    return Unmanaged.passRetained(event) 
                }
                
                let manager = Unmanaged<TrayLangManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleKeyCaptureEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        if let keyCaptureEventTap = keyCaptureEventTap {
            keyCaptureRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyCaptureEventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keyCaptureRunLoopSource, .commonModes)
            CGEvent.tapEnable(tap: keyCaptureEventTap, enable: true)
            print("✅ Захват клавиш запущен успешно")
        } else {
            print("❌ Не удалось создать event tap для захвата")
        }
    }
    
    func stopKeyCapture() {
        print("🛑 Остановка захвата клавиш...")
        
        if let keyCaptureEventTap = keyCaptureEventTap {
            CGEvent.tapEnable(tap: keyCaptureEventTap, enable: false)
            print("✅ Event tap отключен")
        }
        
        if let keyCaptureRunLoopSource = keyCaptureRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), keyCaptureRunLoopSource, .commonModes)
            print("✅ Run loop source удален")
        }
        
        keyCaptureEventTap = nil
        keyCaptureRunLoopSource = nil
        print("🛑 Захват клавиш остановлен")
    }
    
    private func handleKeyCaptureEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        print("🔍 Захват: Клавиша \(keyCode), Флаги \(flags.rawValue)")
        
        // Проверяем, что это действительно событие нажатия клавиши
        guard type == .keyDown else {
            print("⚠️ Игнорируем событие типа \(type.rawValue)")
            return Unmanaged.passRetained(event)
        }
        
        // Проверяем, что keyCode валидный
        guard keyCode > 0 else {
            print("⚠️ Игнорируем событие с keyCode = 0")
            return Unmanaged.passRetained(event)
        }
        
        // Собираем все активные модификаторы
        var modifiers: [CGEventFlags] = []
        if flags.contains(.maskCommand) { 
            modifiers.append(.maskCommand)
            print("  - Command")
        }
        if flags.contains(.maskShift) { 
            modifiers.append(.maskShift)
            print("  - Shift")
        }
        if flags.contains(.maskAlternate) { 
            modifiers.append(.maskAlternate)
            print("  - Option")
        }
        if flags.contains(.maskControl) { 
            modifiers.append(.maskControl)
            print("  - Control")
        }
        
        print("📋 Собранные модификаторы: \(modifiers.map { $0.rawValue })")
        
        // Отправляем уведомление с захваченными данными
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .keyCaptured,
                object: nil,
                userInfo: [
                    "keyCode": keyCode,
                    "modifiers": modifiers
                ]
            )
            print("📤 Отправлено уведомление о захвате клавиши: \(keyCode)")
        }
        
        return nil // Поглощаем событие
    }
    
    // MARK: - Layout Management
    private func getCurrentLayoutName() -> String {
        if let currentLayout = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let namePtr = TISGetInputSourceProperty(currentLayout, kTISPropertyLocalizedName) {
            return Unmanaged<CFString>.fromOpaque(namePtr).takeRetainedValue() as String
        }
        return "Unknown"
    }
    
    private func updateCurrentLayout() {
        if let currentLayout = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            if let namePtr = TISGetInputSourceProperty(currentLayout, kTISPropertyLocalizedName) {
                let name = Unmanaged<CFString>.fromOpaque(namePtr).takeRetainedValue() as String
                self.currentLayout = name
            }
        }
    }
    
    private func loadAvailableLayouts() {
        if let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] {
            availableLayouts = inputSources.compactMap { inputSource in
                if let namePtr = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
                    let name = Unmanaged<CFString>.fromOpaque(namePtr).takeRetainedValue() as String
                    return name
                }
                return nil
            }
        }
    }
    
    func switchToLayout(_ layoutName: String) {
        let inputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        
        for source in inputSources {
            if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                let name = Unmanaged<CFString>.fromOpaque(namePtr).takeRetainedValue() as String
                if name == layoutName {
                    TISSelectInputSource(source)
                    currentLayout = layoutName
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.updateCurrentLayout()
                    }
                    break
                }
            }
        }
    }
    
    // MARK: - Text Transformation
    func transformText(_ text: String, fromRussian: Bool) -> String {
        var result = ""
        
        for char in text {
            let charString = String(char)
            
            // Проверяем, является ли символ буквой
            if char.isLetter {
                // Определяем язык для каждой буквы отдельно
                let isRussianChar = isRussianCharacter(charString)
                let isEnglishChar = isEnglishCharacter(charString)
                
                if isRussianChar {
                    // Русская буква - переводим в английскую
                    if let mapped = fromToMapping[charString] {
                        result += mapped
                    } else {
                        result += charString // Оставляем как есть, если нет соответствия
                    }
                } else if isEnglishChar {
                    // Английская буква - переводим в русскую
                    if let mapped = toFromMapping[charString] {
                        result += mapped
                    } else {
                        result += charString // Оставляем как есть, если нет соответствия
                    }
                } else {
                    // Неизвестная буква - оставляем как есть
                    result += charString
                }
            } else {
                // Не буква - оставляем как есть
                result += charString
            }
        }
        
        return result
    }
    
    private func isRussianCharacter(_ char: String) -> Bool {
        let lowerChar = char.lowercased()
        return fromToMapping.keys.contains(lowerChar)
    }
    
    private func isEnglishCharacter(_ char: String) -> Bool {
        let lowerChar = char.lowercased()
        return toFromMapping.keys.contains(lowerChar)
    }
    
    private func determineTextLanguage(_ text: String) -> Bool {
        // В новой логике каждая буква обрабатывается отдельно
        let textChars = Set(text.lowercased().map { String($0) })
        let russianCount = textChars.intersection(fromToMapping.keys).count
        let englishCount = textChars.intersection(toFromMapping.keys).count
        
        return russianCount > englishCount
    }
    
    // Публичная функция для обратной совместимости
    func detectLanguage(_ text: String) -> Bool {
        return determineTextLanguage(text)
    }
    
    private func transformText(_ text: String) -> String {
        // Новая логика - каждая буква обрабатывается отдельно
        return transformText(text, fromRussian: false) // fromRussian больше не используется
    }
    
    private func getSelectedText() -> String? {
        print("🔍 Получаем выделенный текст через Accessibility API...")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("❌ Не удалось получить активное приложение")
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Метод 1: Попытка получить выделенный текст через kAXSelectedTextAttribute
        if let text = getSelectedTextViaAttribute(appElement) {
            return text
        }
        
        // Метод 2: Попытка получить текст через kAXValueAttribute
        if let text = getSelectedTextViaValue(appElement) {
            return text
        }
        
        // Метод 3: Попытка получить текст через AppleScript и горячие клавиши
        if let text = getSelectedTextViaHotkeys() {
            return text
        }
        
        print("❌ Не удалось получить выделенный текст ни одним из методов")
        return nil
    }
    
    private func getSelectedTextViaAttribute(_ appElement: AXUIElement) -> String? {
        // Получаем фокусный элемент
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            print("❌ Не удалось получить фокусный элемент")
            return nil
        }
        
        // Получаем выделенный текст
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            print("📋 Получен текст через kAXSelectedTextAttribute: \(text)")
            return text
        }
        
        return nil
    }
    
    private func getSelectedTextViaValue(_ appElement: AXUIElement) -> String? {
        // Получаем фокусный элемент
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            return nil
        }
        
        // Получаем значение элемента
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &value)
        
        if valueResult == .success, let text = value as? String, !text.isEmpty {
            print("📋 Получен текст через kAXValueAttribute: \(text)")
            return text
        }
        
        return nil
    }
    

    
    private func replaceSelectedText(with newText: String) {
        print("📝 Заменяем выделенный текст на: \(newText)")
        
        // Метод 1: Попытка заменить через улучшенную логику (наиболее надежный)
        if replaceTextWithImprovedLogic(newText) {
            return
        }
        
        // Метод 2: Попытка заменить через Accessibility API (резервный)
        if replaceTextViaAccessibility(newText) {
            return
        }
        
        print("❌ Не удалось заменить текст ни одним из методов")
    }
    
    private func replaceTextViaAccessibility(_ newText: String) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("❌ Не удалось получить активное приложение")
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Получаем фокусный элемент
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            print("❌ Не удалось получить фокусный элемент")
            return false
        }
        
        // Пытаемся получить текущий текст для проверки
        var currentText: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &currentText)
        
        if getResult == .success, let text = currentText as? String {
            print("📋 Текущий текст элемента: \(text)")
            
            // Пытаемся получить выделенный текст
            var selectedText: CFTypeRef?
            let selectedResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
            
            if selectedResult == .success, let selected = selectedText as? String, !selected.isEmpty {
                print("📋 Выделенный текст: \(selected)")
                
                // Заменяем выделенный текст на новый
                let setResult = AXUIElementSetAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, newText as CFString)
                
                if setResult == .success {
                    print("✅ Выделенный текст успешно заменен через Accessibility API")
                    return true
                }
            }
        }
        
        print("❌ Не удалось заменить текст через Accessibility API")
        return false
    }
    

    
    private func getSelectedTextViaHotkeys() -> String? {
        print("📋 Пытаемся получить текст через AppleScript...")
        
        // Используем AppleScript для получения выделенного текста с сохранением позиции
        let script = """
        tell application "System Events"
            set originalClipboard to the clipboard
            try
                -- Копируем выделенный текст (Cmd+C)
                key code 8 using {command down}
                delay 0.1
                set selectedText to the clipboard
                -- Восстанавливаем оригинальный буфер обмена
                set the clipboard to originalClipboard
                return selectedText
            on error
                -- Восстанавливаем оригинальный буфер обмена в случае ошибки
                set the clipboard to originalClipboard
                return ""
            end try
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if !output.isEmpty && output != "error" {
                    print("📋 Получен текст через AppleScript: \(output)")
                    return output
                }
            }
        } catch {
            print("❌ Ошибка при выполнении AppleScript: \(error)")
        }
        
        return nil
    }
    

    
    // MARK: - Improved Text Replacement
    private func replaceTextWithImprovedLogic(_ newText: String) -> Bool {
        print("🔍 Пытаемся заменить текст с улучшенной логикой...")
        
        // Используем AppleScript для замены текста с более продвинутой обработкой выделения
        let script = """
        tell application "System Events"
            set originalClipboard to the clipboard
            try
                -- Проверяем, есть ли выделенный текст
                key code 8 using {command down}
                delay 0.1
                set selectedText to the clipboard
                
                if selectedText is not equal to originalClipboard then
                    -- Есть выделенный текст, заменяем его
                    set the clipboard to "\(newText)"
                    delay 0.1
                    key code 9 using {command down}
                    delay 0.1
                    set the clipboard to originalClipboard
                    return "success"
                else
                    -- Нет выделенного текста, просто вставляем
                    set the clipboard to "\(newText)"
                    delay 0.1
                    key code 9 using {command down}
                    delay 0.1
                    set the clipboard to originalClipboard
                    return "success"
                end if
            on error
                -- Восстанавливаем оригинальный буфер обмена в случае ошибки
                set the clipboard to originalClipboard
                return "error"
            end try
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output == "success" {
                    print("✅ Текст успешно заменен с улучшенной логикой")
                    return true
                }
            }
        } catch {
            print("❌ Ошибка при выполнении AppleScript: \(error)")
        }
        
        return false
    }
    
    private func transformSelectedText() -> String? {
        guard let selectedText = getSelectedText(), !selectedText.isEmpty else {
            print("❌ Не удалось получить выделенный текст")
            return nil
        }
        
        print("📋 Выделенный текст: \(selectedText)")
        
        // Трансформируем текст
        let transformedText = transformText(selectedText)
        print("🔄 Трансформированный текст: \(transformedText)")
        
        // Заменяем выделенный текст
        replaceSelectedText(with: transformedText)
        
        return transformedText
    }
    
    // MARK: - Main Action
    func performLayoutSwitch() {
        print("🔄 Выполняем переключение раскладки...")
        
        // Проверяем разрешения на доступность
        if !AXIsProcessTrusted() {
            print("⚠️ Требуются разрешения на доступность")
            requestAccessibilityPermissions()
            return
        }
        
        // Получаем информацию о текущем приложении
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            print("📱 Активное приложение: \(frontmostApp.localizedName ?? "Unknown") (PID: \(frontmostApp.processIdentifier))")
        }
        
        // Получаем выделенный текст
        guard let selectedText = getSelectedText(), !selectedText.isEmpty else {
            print("❌ Не удалось получить выделенный текст")
            print("💡 Попробуйте выделить текст и нажать горячую клавишу снова")
            return
        }
        
        print("📋 Выделенный текст: \(selectedText)")
        
        // Трансформируем текст
        let transformedText = transformText(selectedText)
        print("🔄 Трансформированный текст: \(transformedText)")
        
        // Заменяем текст
        replaceSelectedText(with: transformedText)
        
        // Переключаем раскладку клавиатуры
        switchKeyboardLayout()
        
        print("✅ Переключение раскладки завершено")
    }
    
    private func switchKeyboardLayout() {
        let currentLayout = getCurrentLayoutName()
        print("🔍 Текущая раскладка: \(currentLayout)")
        
        if currentLayout.contains("Russian") || currentLayout.contains("Русская") {
            // Переключаем на английскую
            if let englishLayout = availableLayouts.first(where: { $0.contains("ABC") || $0.contains("English") }) {
                switchToLayout(englishLayout)
                print("🔄 Переключено на английскую раскладку")
            }
        } else {
            // Переключаем на русскую
            if let russianLayout = availableLayouts.first(where: { $0.contains("Russian") || $0.contains("Русская") }) {
                switchToLayout(russianLayout)
                print("🔄 Переключено на русскую раскладку")
            }
        }
    }
    
    // MARK: - Notifications
    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Ошибка отправки уведомления: \(error)")
            }
        }
    }
    
    // MARK: - Persistence
    func saveHotKey() {
        if let data = try? JSONEncoder().encode(hotKey) {
            UserDefaults.standard.set(data, forKey: "savedHotKey")
        }
    }
    
    func loadHotKey() {
        if let data = UserDefaults.standard.data(forKey: "savedHotKey"),
           let savedHotKey = try? JSONDecoder().decode(HotKey.self, from: data) {
            DispatchQueue.main.async {
                self.hotKey = savedHotKey
            }
        }
    }
    
    // MARK: - Auto Launch
    func enableAutoLaunch() {
        do {
            // Используем современный SMAppService
            let appService = SMAppService.mainApp
            try appService.register()
            
            UserDefaults.standard.set(true, forKey: "autoLaunchEnabled")
            print("✅ Автозапуск включен через SMAppService")
        } catch {
            print("❌ Ошибка включения автозапуска: \(error)")
        }
    }
    
    func disableAutoLaunch() {
        do {
            // Отключаем автозапуск через SMAppService
            let appService = SMAppService.mainApp
            try appService.unregister()
            
            UserDefaults.standard.set(false, forKey: "autoLaunchEnabled")
            print("✅ Автозапуск отключен")
        } catch {
            print("❌ Ошибка отключения автозапуска: \(error)")
        }
    }
    
    func isAutoLaunchEnabled() -> Bool {
        do {
            // Проверяем статус через SMAppService
            let appService = SMAppService.mainApp
            return appService.status == .enabled
        } catch {
            // Если не удалось проверить, используем UserDefaults
            return UserDefaults.standard.bool(forKey: "autoLaunchEnabled")
        }
    }

    func addSymbolMapping(from: String, to: String) {
        let lowerFrom = from.lowercased()
        let lowerTo = to.lowercased()
        fromToMapping[lowerFrom] = lowerTo
        toFromMapping[lowerTo] = lowerFrom
    }
    
    func updateSymbolMapping(from: String, to: String) {
        let lowerFrom = from.lowercased()
        let lowerTo = to.lowercased()
        
        // Удаляем старые соответствия
        fromToMapping.removeValue(forKey: lowerFrom)
        toFromMapping.removeValue(forKey: lowerTo)
        
        // Добавляем новые соответствия
        fromToMapping[lowerFrom] = lowerTo
        toFromMapping[lowerTo] = lowerFrom
        saveSymbols()
    }
    
    func removeSymbolMapping(from: String) {
        let lowerFrom = from.lowercased()
        fromToMapping.removeValue(forKey: lowerFrom)
        saveSymbols()
    }
    
    private func saveSymbols() {
        // Сохраняем маппинги
        if let data = try? JSONEncoder().encode(fromToMapping) {
            UserDefaults.standard.set(data, forKey: "fromToMapping")
        }
        if let data = try? JSONEncoder().encode(toFromMapping) {
            UserDefaults.standard.set(data, forKey: "toFromMapping")
        }
    }
    
    private func loadSymbols() {
        // Загружаем маппинги
        if let data = UserDefaults.standard.data(forKey: "fromToMapping"),
           let mapping = try? JSONDecoder().decode([String: String].self, from: data) {
            fromToMapping = mapping
        }
        if let data = UserDefaults.standard.data(forKey: "toFromMapping"),
           let mapping = try? JSONDecoder().decode([String: String].self, from: data) {
            toFromMapping = mapping
        }
    }
}

// MARK: - HotKey Structure
struct HotKey: Codable {
    let keyCode: Int
    let modifiers: [CGEventFlags]
    
    var description: String {
        let modifierString = modifiers.map { flag in
            switch flag {
            case .maskCommand: return "⌘"
            case .maskShift: return "⇧"
            case .maskAlternate: return "⌥"
            case .maskControl: return "⌃"
            default: return ""
            }
        }.joined()
        
        let keyString = getKeyName(for: keyCode)
        return "\(modifierString)\(keyString)"
    }
    
    private func getKeyName(for keyCode: Int) -> String {
        return TrayLangManager.getAvailableKeyCodes().first { $0.keyCode == keyCode }?.name ?? "?"
    }
    
    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }
    
    init(keyCode: Int, modifiers: [CGEventFlags]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        let modifierRawValues = try container.decode([UInt64].self, forKey: .modifiers)
        modifiers = modifierRawValues.map { CGEventFlags(rawValue: $0) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        let modifierRawValues = modifiers.map { $0.rawValue }
        try container.encode(modifierRawValues, forKey: .modifiers)
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let hotKeyPressed = Notification.Name("hotKeyPressed")
    static let keyCaptured = Notification.Name("keyCaptured")
}