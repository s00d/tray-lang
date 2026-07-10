import XCTest

final class SettingsWindowUITests: XCTestCase {

    private let bundleIdentifier = "os.s00d.tray-lang.debug"

    override func tearDownWithError() throws {
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 10)
        }
    }

    @MainActor
    func testSettingsWindowOpensFromLaunchArgument() throws {
        let existingApp = XCUIApplication(bundleIdentifier: bundleIdentifier)
        if existingApp.state != .notRunning {
            existingApp.terminate()
            XCTAssertTrue(existingApp.wait(for: .notRunning, timeout: 10))
        }

        let app = XCUIApplication()
        app.launchArguments = ["-openSettings"]
        app.launch()

        let settingsWindow = app.windows.matching(
            NSPredicate(format: "identifier == %@", "tray-lang.settings")
        ).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Accessibility"].waitForExistence(timeout: 5))
    }
}
