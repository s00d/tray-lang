import Foundation
import ServiceManagement

// MARK: - Auto Launch Manager
class AutoLaunchManager: ObservableObject {
    
    init() {}
    
    // MARK: - Auto Launch Management
    func enableAutoLaunch() {
        do {
            let appService = SMAppService.mainApp
            try appService.register()
            print("✅ Автозапуск включен")
        } catch {
            print("❌ Ошибка включения автозапуска: \(error)")
        }
    }
    
    func disableAutoLaunch() {
        do {
            let appService = SMAppService.mainApp
            try appService.unregister()
            print("⏹️ Автозапуск отключен")
        } catch {
            print("❌ Ошибка отключения автозапуска: \(error)")
        }
    }
    
    func isAutoLaunchEnabled() -> Bool {
        let appService = SMAppService.mainApp
        return appService.status == .enabled
    }
} 