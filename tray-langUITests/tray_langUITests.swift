//
//  tray_langUITests.swift
//  tray-langUITests
//
//  Created by s00d on 01.08.2025.
//

import XCTest

final class tray_langUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAccessibilityPrompt"]
        app.launch()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-skipAccessibilityPrompt"]
            app.launch()
        }
    }
}
