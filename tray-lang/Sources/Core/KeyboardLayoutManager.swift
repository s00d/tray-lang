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
    }
    
    func updateCurrentLayout() {
        let newLayout = getCurrentSystemLayout()
        if newLayout != currentLayout {
            currentLayout = newLayout
            print("[KeyboardLayoutManager] Layout changed to: \(currentLayout)")
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
                layouts.append(id)
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
} 