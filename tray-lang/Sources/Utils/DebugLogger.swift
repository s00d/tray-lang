import Foundation

/// Debug logger that only prints in DEBUG builds
func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

