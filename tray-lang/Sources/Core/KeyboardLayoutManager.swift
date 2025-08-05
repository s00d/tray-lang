import Foundation
import AppKit
import Carbon

// MARK: - Keyboard Layout Manager
class KeyboardLayoutManager: ObservableObject {
    @Published var currentLayout: String = "Unknown"
    @Published var availableLayouts: [String] = []
    
    private var layoutCheckTimer: Timer?
    
    init() {
        loadAvailableLayouts()
        updateCurrentLayout()
        startLayoutMonitoring()
    }
    
    deinit {
        layoutCheckTimer?.invalidate()
    }
    
    // MARK: - Layout Management
    func loadAvailableLayouts() {
        availableLayouts = getSystemLayouts()
        print("[KeyboardLayoutManager] Available layouts: \(availableLayouts)")
    }
    
    func updateCurrentLayout() {
        let newLayout = getCurrentSystemLayout()
        if newLayout != currentLayout {
            currentLayout = newLayout
            print("[KeyboardLayoutManager] Layout changed to: \(currentLayout)")
        }
    }
    
    func switchToNextLayout() {
        guard !availableLayouts.isEmpty else {
            print("[KeyboardLayoutManager] No available layouts")
            return
        }
        
        let currentIndex = availableLayouts.firstIndex(of: currentLayout) ?? 0
        let nextIndex = (currentIndex + 1) % availableLayouts.count
        let nextLayout = availableLayouts[nextIndex]
        
        print("[KeyboardLayoutManager] Switching from '\(currentLayout)' to '\(nextLayout)'")
        
        // Переключаем на следующую раскладку
        if let inputSource = getInputSource(for: nextLayout) {
            let result = TISSelectInputSource(inputSource)
            if result == noErr {
                print("[KeyboardLayoutManager] Successfully switched to '\(nextLayout)'")
                currentLayout = nextLayout
            } else {
                print("[KeyboardLayoutManager] Failed to switch to '\(nextLayout)', error: \(result)")
            }
        } else {
            print("[KeyboardLayoutManager] Could not find input source for '\(nextLayout)'")
        }
    }
    
    private func startLayoutMonitoring() {
        layoutCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCurrentLayout()
        }
    }
    
    // MARK: - System Integration
    private func getSystemLayouts() -> [String] {
        guard let inputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        var layouts: [String] = []
        for source in inputSources {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                // Фильтруем только основные языки ввода
                if !id.contains("CharacterPaletteIM") && 
                   !id.contains("Emoji") && 
                   !id.contains("Pinyin") &&
                   !id.contains("Handwriting") &&
                   !id.contains("PressAndHold") {
                    layouts.append(id)
                }
            }
        }
        return layouts
    }
    
    private func getCurrentSystemLayout() -> String {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "Unknown"
        }
        if let idPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            return id
        }
        return "Unknown"
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