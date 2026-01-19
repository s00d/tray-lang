import Foundation
import Carbon
import AppKit

// MARK: - Hot Key Manager
class HotKeyManager: ObservableObject {
    @Published var hotKey: HotKey = HotKey(keyCode: 18, modifiers: [.maskCommand])
    
    // 1. УБИРАЕМ didSet.
    @Published var isEnabled: Bool = false
    @Published var isSecureInputActive: Bool = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Отдельный поток для мониторинга клавиатуры
    private var monitoringThread: Thread?
    private var monitoringRunLoop: CFRunLoop?
    
    // Таймер для мониторинга Secure Input
    private var secureInputTimer: Timer?
    
    init() {
        // 2. УБИРАЕМ загрузку isEnabled из init.
        loadHotKey()
    }
    
    deinit {
        stopMonitoring()
        stopSecureInputMonitoring()
    }
    
    // 3. ДОБАВЛЯЕМ функцию сохранения isEnabled, которую будет вызывать AppCoordinator
    func saveEnabledState() {
        UserDefaults.standard.set(isEnabled, forKey: "hotKeyMonitoringEnabled")
    }
    
    // MARK: - Hot Key Management
    func loadHotKey() {
        if let savedHotKey = UserDefaults.standard.object(forKey: "savedHotKey") as? Data {
            do {
                let decoder = JSONDecoder()
                hotKey = try decoder.decode(HotKey.self, from: savedHotKey)
            } catch {
                debugLog("❌ Ошибка загрузки горячей клавиши: \(error)")
            }
        }
    }
    
    func saveHotKey() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(hotKey)
            UserDefaults.standard.set(data, forKey: "savedHotKey")
        } catch {
                debugLog("❌ Ошибка сохранения горячей клавиши: \(error)")
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
        
        debugLog("🔄 Хоткей обновлен: \(newHotKey.displayString)")
    }
    
    // MARK: - Monitoring
    func startMonitoring() {
        guard !isEnabled else { return }
        
        // Запускаем мониторинг Secure Input
        startSecureInputMonitoring()
        
        // Создаем поток для мониторинга
        monitoringThread = Thread { [weak self] in
            guard let self = self else { return }
            
            let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            
            self.eventTap = CGEvent.tapCreate(
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
            
            guard let eventTap = self.eventTap else {
                debugLog("❌ Не удалось создать event tap")
                return
            }
            
            self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            let currentRunLoop = CFRunLoopGetCurrent()
            self.monitoringRunLoop = currentRunLoop
            CFRunLoopAddSource(currentRunLoop, self.runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            
            DispatchQueue.main.async {
                self.isEnabled = true
            }
            
            debugLog("✅ Мониторинг горячих клавиш запущен")
            
            // Запускаем RunLoop этого потока
            CFRunLoopRun()
        }
        
        monitoringThread?.name = "com.traylang.hotkeyMonitor"
        monitoringThread?.qualityOfService = .userInteractive
        monitoringThread?.start()
    }
    
    func stopMonitoring() {
        guard isEnabled else { return }
        
        // Останавливаем мониторинг Secure Input
        stopSecureInputMonitoring()
        
        // Останавливаем RunLoop потока
        if let runLoop = monitoringRunLoop {
            CFRunLoopStop(runLoop)
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource, let runLoop = monitoringRunLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        monitoringRunLoop = nil
        
        // Отменяем поток
        monitoringThread?.cancel()
        monitoringThread = nil
        
        isEnabled = false
        debugLog("⏹️ Мониторинг горячих клавиш остановлен")
    }
    
    // MARK: - Event Handling
    private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Обрабатываем отключение Event Tap системой
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            debugLog("⚠️ Event Tap disabled by system (type: \(type.rawValue)). Attempting to re-enable...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                debugLog("🔄 Event Tap re-enabled")
            }
            return nil
        }
        
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Проверяем, соответствует ли событие нашей горячей клавише
        if keyCode == hotKey.keyCode && flags.contains(hotKey.modifiers.first ?? []) {
            debugLog("🎯 Горячая клавиша сработала!")
            NotificationCenter.default.post(name: .hotKeyPressed, object: nil)
            return nil // Поглощаем событие
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - Secure Input Monitoring
    private func startSecureInputMonitoring() {
        // Проверяем состояние сразу
        checkSecureInput()
        
        // Запускаем таймер для периодической проверки (каждые 2 секунды)
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkSecureInput()
        }
        
        debugLog("✅ Мониторинг Secure Input запущен")
    }
    
    private func stopSecureInputMonitoring() {
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        debugLog("⏹️ Мониторинг Secure Input остановлен")
    }
    
    private func checkSecureInput() {
        let isSecure = IsSecureEventInputEnabled()
        
        // Обновляем состояние только если оно изменилось
        if isSecureInputActive != isSecure {
            DispatchQueue.main.async {
                self.isSecureInputActive = isSecure
                if isSecure {
                    debugLog("⚠️ Secure Input активен - перехват клавиш может не работать")
                } else {
                    debugLog("✅ Secure Input деактивирован - перехват клавиш работает")
                }
            }
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let hotKeyPressed = Notification.Name("hotKeyPressed")
}
