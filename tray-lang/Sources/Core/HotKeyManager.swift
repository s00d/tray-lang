import Foundation
import Carbon
import AppKit

// MARK: - Hot Key Manager
class HotKeyManager: ObservableObject {
    @Published var hotKey: HotKey = HotKey(keyCode: 18, modifiers: [.maskCommand])
    @Published var isEnabled: Bool = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    init() {
        loadHotKey()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Hot Key Management
    func loadHotKey() {
        if let savedHotKey = UserDefaults.standard.object(forKey: "savedHotKey") as? Data {
            do {
                let decoder = JSONDecoder()
                hotKey = try decoder.decode(HotKey.self, from: savedHotKey)
            } catch {
                print("❌ Ошибка загрузки горячей клавиши: \(error)")
            }
        }
    }
    
    func saveHotKey() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(hotKey)
            UserDefaults.standard.set(data, forKey: "savedHotKey")
        } catch {
            print("❌ Ошибка сохранения горячей клавиши: \(error)")
        }
    }
    
    func updateHotKey(_ newHotKey: HotKey) {
        let wasEnabled = isEnabled
        
        // Останавливаем текущий мониторинг
        if wasEnabled {
            stopMonitoring()
            // Небольшая задержка для завершения остановки
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Обновляем хоткей
        hotKey = newHotKey
        
        // Сохраняем новый хоткей
        saveHotKey()
        
        // Перезапускаем мониторинг если он был активен
        if wasEnabled {
            startMonitoring()
        }
        
        print("🔄 Хоткей обновлен: \(newHotKey.displayString)")
    }
    
    // MARK: - Monitoring
    func startMonitoring() {
        guard !isEnabled else { return }
        
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            print("❌ Не удалось создать event tap")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isEnabled = true
        print("✅ Мониторинг горячих клавиш запущен")
    }
    
    func stopMonitoring() {
        guard isEnabled else { return }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isEnabled = false
        print("⏹️ Мониторинг горячих клавиш остановлен")
    }
    
    // MARK: - Event Handling
    private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Проверяем, соответствует ли событие нашей горячей клавише
        if keyCode == hotKey.keyCode && flags.contains(hotKey.modifiers.first ?? []) {
            print("🎯 Горячая клавиша сработала!")
            NotificationCenter.default.post(name: .hotKeyPressed, object: nil)
            return nil // Поглощаем событие
        }
        
        return Unmanaged.passUnretained(event)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let hotKeyPressed = Notification.Name("hotKeyPressed")
} 