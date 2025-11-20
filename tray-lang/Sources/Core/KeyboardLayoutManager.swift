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
    
    // Новый универсальный метод для извлечения информации
    private func extractLayoutInfo(from source: TISInputSource) -> KeyboardLayout? {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        
        let layoutID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        let localizedName = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        var shortName = "??".uppercased()

        // Самый надежный способ: получаем языковой код (ISO 639)
        if let langPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
           let languages = Unmanaged<CFArray>.fromOpaque(langPtr).takeUnretainedValue() as? [String],
           let firstLang = languages.first {
            shortName = firstLang.uppercased()
        } else {
            // Фолбэк: если языковой код не указан, пытаемся угадать по ID
            if layoutID.lowercased().contains("abc") || layoutID.lowercased().contains("us") {
                shortName = "EN"
            } else {
                let components = layoutID.split(separator: ".")
                if let lastComponent = components.last {
                    shortName = String(lastComponent.prefix(2)).uppercased()
                }
            }
        }
        
        return KeyboardLayout(id: layoutID, localizedName: localizedName, shortName: shortName)
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