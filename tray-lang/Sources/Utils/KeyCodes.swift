import Foundation

// MARK: - Key Code Utility
struct KeyCodes {
    static let keyNames: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9", 29: "0", 27: "-", 24: "=", 33: "[", 30: "]",
        42: "\\", 39: ";", 41: "'", 43: ",", 47: ".", 44: "/", 50: "`"
    ]
    
    static func getKeyName(for keyCode: Int) -> String {
        return keyNames[keyCode] ?? "Key \(keyCode)"
    }
}