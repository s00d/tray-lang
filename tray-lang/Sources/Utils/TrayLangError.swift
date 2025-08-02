import Foundation

// MARK: - Application Errors
enum TrayLangError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case textRetrievalFailed
    case textReplacementFailed
    case hotKeyRegistrationFailed
    case layoutSwitchFailed
    case clipboardAccessFailed
    
    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permissions are required for this application to function properly."
        case .textRetrievalFailed:
            return "Failed to retrieve selected text from the active application."
        case .textReplacementFailed:
            return "Failed to replace text in the active application."
        case .hotKeyRegistrationFailed:
            return "Failed to register hot key monitoring."
        case .layoutSwitchFailed:
            return "Failed to switch keyboard layout."
        case .clipboardAccessFailed:
            return "Failed to access clipboard."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Please grant accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility."
        case .textRetrievalFailed:
            return "Make sure text is selected in the active application and try again."
        case .textReplacementFailed:
            return "The application may not support text replacement. Try selecting text again."
        case .hotKeyRegistrationFailed:
            return "Restart the application and try again."
        case .layoutSwitchFailed:
            return "Check your keyboard layout settings in System Preferences."
        case .clipboardAccessFailed:
            return "Check if another application is using the clipboard."
        }
    }
} 