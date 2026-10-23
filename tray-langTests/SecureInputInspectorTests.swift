import XCTest
@testable import tray_lang

final class SecureInputInspectorTests: XCTestCase {

    func testProcessNameResolvesCurrentProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let name = SecureInputInspector.processName(for: pid)
        XCTAssertNotNil(name)
        XCTAssertFalse(name?.isEmpty == true)
    }

    func testReadsHolderPIDFromSessionDictionary() {
        let session: [String: Any] = ["kCGSSessionOnConsoleKey": true, "kCGSSessionSecureInputPID": NSNumber(value: 30171), "kCGSSessionUserNameKey": "s00d"]
        XCTAssertEqual(SecureInputInspector.holderPID(in: session), 30171)
        XCTAssertNil(SecureInputInspector.holderPID(in: ["kCGSSessionOnConsoleKey": true]))
        XCTAssertNil(SecureInputInspector.holderPID(in: ["kCGSSessionSecureInputPID": NSNumber(value: 0)]))
    }

    func testLookupDoesNotCrashAndMatchesSecureInputState() {
        // Without Secure Input on there is no holder; with it on, the holder is a real process.
        if let pid = SecureInputInspector.holderPID() {
            XCTAssertTrue(SecureInputInspector.isProcessRunning(pid) || !SecureInputInspector.isActive())
        }
    }

    func testDetectsStaleHolderWhenPIDIsNotRunning() {
        XCTAssertFalse(SecureInputInspector.isProcessRunning(pid_t(9_999_999)))
    }
}
