import Foundation
import ServiceManagement

/// Launch at login via `SMAppService.mainApp`; the system status is the only source of truth.
final class AutoLaunchManager {
    private let service = SMAppService.mainApp

    var isEnabled: Bool { service.status == .enabled }

    /// Needs the user's OK in System Settings › General › Login Items.
    var requiresApproval: Bool { service.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
