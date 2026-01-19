import Foundation
import AppKit
import Carbon

// MARK: - Keyboard Layout Structure
struct KeyboardLayout: Identifiable, Hashable {
    var id: String // e.g., com.apple.keylayout.Russian
    var localizedName: String // e.g., "Русская"
    var shortName: String // e.g., "RU"
}

// MARK: - Keyboard Layout Manager
class KeyboardLayoutManager: ObservableObject {
    @Published var currentLayout: KeyboardLayout?
    @Published var availableLayouts: [KeyboardLayout] = []
    
    init() {
        loadAvailableLayouts()
        updateCurrentLayout()
        startLayoutMonitoring()
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    // MARK: - Layout Management
    func loadAvailableLayouts() {
        availableLayouts = getSystemLayouts()
        print("[KeyboardLayoutManager] Available layouts loaded: \(availableLayouts.count)")
    }
    
    func updateCurrentLayout() {
        let newLayout = getCurrentSystemLayout()
        if newLayout != currentLayout {
            currentLayout = newLayout
            if let layout = newLayout {
                print("[KeyboardLayoutManager] Layout changed to: \(layout.localizedName) (\(layout.shortName))")
            }
        }
    }
    
    func switchToNextLayout() {
        guard !availableLayouts.isEmpty, let current = currentLayout else {
            print("[KeyboardLayoutManager] No available layouts or current layout is unknown.")
            return
        }
        
        let currentIndex = availableLayouts.firstIndex(of: current) ?? 0
        let nextIndex = (currentIndex + 1) % availableLayouts.count
        let nextLayout = availableLayouts[nextIndex]
        
        print("[KeyboardLayoutManager] Switching from '\(current.localizedName)' to '\(nextLayout.localizedName)'")
        
        if let inputSource = getInputSource(for: nextLayout.id) {
            let result = TISSelectInputSource(inputSource)
            if result == noErr {
                currentLayout = nextLayout
                print("[KeyboardLayoutManager] Successfully switched to '\(nextLayout.localizedName)'")
            } else {
                print("[KeyboardLayoutManager] Failed to switch to '\(nextLayout.localizedName)', error: \(result)")
            }
        }
    }
    
    func switchToLayout(id layoutID: String) {
        if let inputSource = getInputSource(for: layoutID) {
            TISSelectInputSource(inputSource)
        }
    }
    
    private func startLayoutMonitoring() {
        // Используем системное уведомление вместо таймера
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(layoutChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }
    
    @objc private func layoutChanged() {
        // Важно: UI обновляем на главном потоке
        DispatchQueue.main.async { [weak self] in
            self?.updateCurrentLayout()
        }
    }
    
    // MARK: - System Integration
    
    // УЛУЧШЕННЫЙ универсальный метод для извлечения информации о раскладке
    private func extractLayoutInfo(from source: TISInputSource) -> KeyboardLayout? {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        
        let layoutID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        let localizedName = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        var shortName = ""

        // МЕТОД 1: Получаем языковой код (ISO 639) - самый надежный способ
        if let langPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
           let languages = Unmanaged<CFArray>.fromOpaque(langPtr).takeUnretainedValue() as? [String],
           let firstLang = languages.first {
            shortName = normalizeLanguageCode(firstLang)
        }
        
        // МЕТОД 2: Если языковой код не найден, пытаемся определить по ID раскладки
        if shortName.isEmpty {
            shortName = extractShortNameFromLayoutID(layoutID)
        }
        
        // МЕТОД 3: Если все еще не найден, берем первые 2 символа из имени
        if shortName.isEmpty {
            shortName = String(localizedName.prefix(2)).uppercased()
        }
        
        // МЕТОД 4: Крайний случай - показываем иконку "неизвестно"
        if shortName.isEmpty {
            shortName = "?" // Показываем один символ вопроса вместо "??"
        }
        
        return KeyboardLayout(id: layoutID, localizedName: localizedName, shortName: shortName)
    }
    
    // Нормализует языковой код ISO 639 в двухбуквенный код
    private func normalizeLanguageCode(_ code: String) -> String {
        // Маппинг известных кодов
        let languageMap: [String: String] = [
            "en": "EN",
            "ru": "RU",
            "ru-Russian": "RU",
            "en-US": "EN",
            "en-GB": "GB",
            "fr": "FR",
            "de": "DE",
            "es": "ES",
            "it": "IT",
            "pt": "PT",
            "ja": "JP",
            "zh": "CN",
            "zh-Hans": "CN",
            "zh-Hant": "TW",
            "ko": "KR",
            "ar": "AR",
            "he": "IL",
            "hi": "IN",
            "uk": "UA",
            "pl": "PL",
            "cs": "CZ",
            "tr": "TR",
            "nl": "NL",
            "sv": "SE",
            "da": "DK",
            "no": "NO",
            "fi": "FI"
        ]
        
        // Если есть точное совпадение, возвращаем его
        if let mapped = languageMap[code] {
            return mapped
        }
        
        // Если код содержит дефис (например, "en-US"), берем первую часть
        if let firstPart = code.split(separator: "-").first {
            let normalized = String(firstPart)
            if let mapped = languageMap[normalized] {
                return mapped
            }
            return normalized.uppercased()
        }
        
        // Иначе просто uppercase первых 2 символов
        return String(code.prefix(2)).uppercased()
    }
    
    // Извлекает короткое имя из ID раскладки
    private func extractShortNameFromLayoutID(_ layoutID: String) -> String {
        // Известные паттерны в ID раскладок
        let idMap: [String: String] = [
            "abc": "EN",
            "us": "EN",
            "russian": "RU",
            "french": "FR",
            "german": "DE",
            "spanish": "ES",
            "italian": "IT",
            "portuguese": "PT",
            "japanese": "JP",
            "chinese": "CN",
            "korean": "KR",
            "arabic": "AR",
            "hebrew": "IL",
            "hindi": "IN",
            "ukrainian": "UA",
            "polish": "PL",
            "czech": "CZ",
            "turkish": "TR",
            "dutch": "NL",
            "swedish": "SE",
            "danish": "DK",
            "norwegian": "NO",
            "finnish": "FI"
        ]
        
        let lowercaseID = layoutID.lowercased()
        
        // Проверяем известные паттерны
        for (pattern, shortName) in idMap {
            if lowercaseID.contains(pattern) {
                return shortName
            }
        }
        
        // Если ничего не найдено, берем последний компонент ID (после последней точки)
        let components = layoutID.split(separator: ".")
        if let lastComponent = components.last {
            return String(lastComponent.prefix(2)).uppercased()
        }
        
        return ""
    }

    private func getSystemLayouts() -> [KeyboardLayout] {
        guard let inputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        
        // Используем compactMap для фильтрации и трансформации
        return inputSources.compactMap { source in
            guard let categoryPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else {
                return nil
            }
            let category = Unmanaged<CFString>.fromOpaque(categoryPtr).takeUnretainedValue() as String
            guard category == (kTISCategoryKeyboardInputSource as String) else {
                return nil
            }
            return extractLayoutInfo(from: source)
        }
    }
    
    private func getCurrentSystemLayout() -> KeyboardLayout? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return extractLayoutInfo(from: currentSource)
    }
    
    private func getInputSource(for layoutID: String) -> TISInputSource? {
        guard let inputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        
        for source in inputSources {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if id == layoutID {
                    return source
                }
            }
        }
        return nil
    }
} 