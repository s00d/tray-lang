import Foundation

/// Prints in Debug builds only; the message is not even built in Release.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
