import XCTest
@testable import tray_lang

final class SecureInputInspectorTests: XCTestCase {

    func testProcessNameResolvesCurrentProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let name = SecureInputInspector.processName(for: pid)
        XCTAssertNotNil(name)
        XCTAssertFalse(name?.isEmpty == true)
    }

    func testParsesSecureInputPIDFromModernIORegFormat() {
        let sample = """
        "IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=Yes,"kCGSSessionSecureInputPID"=30171,"kCGSSessionUserNameKey"="s00d"})
        """

        XCTAssertEqual(SecureInputInspector.parseHolderPID(from: sample), 30171)
    }

    func testParsesSecureInputPIDFromQuotedKeyFormat() {
        let sample = #""kCGSSessionSecureInputPID"=30171"#
        XCTAssertEqual(SecureInputInspector.parseHolderPID(from: sample), 30171)
    }

    func testDetectsStaleHolderWhenPIDIsNotRunning() {
        XCTAssertFalse(SecureInputInspector.isProcessRunning(pid_t(9_999_999)))
    }
}
