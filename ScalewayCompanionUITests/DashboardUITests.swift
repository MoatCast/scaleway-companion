// SPDX-License-Identifier: MPL-2.0

import XCTest

@MainActor
final class DashboardUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_IE"]
        app.launch()
        return app
    }

    func testDashboardNavigationProjectFilteringAndDemoControls() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["spendingTotal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["spendingTotal"].label.contains("42.80"))
        app.buttons["projectPicker"].tap()
        app.buttons["Personal"].tap()
        XCTAssertTrue(app.staticTexts["spendingTotal"].label.contains("6.00"))
        XCTAssertTrue(app.buttons["instance-stage"].exists)
        XCTAssertFalse(app.buttons["instance-api"].exists)
        app.buttons["instance-stage"].tap()
        app.buttons["Simulate start"].tap()
        let confirmation = app.sheets["Simulate start for staging?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        if confirmation.buttons["Cancel"].exists {
            confirmation.buttons["Cancel"].tap()
        } else {
            XCTAssertTrue(app.popovers.firstMatch.exists)
            // Tap the visible detail sheet outside the confirmation popover.
            app.staticTexts["Status"].tap()
        }
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Status, Stopped"].exists)
        app.buttons["Simulate start"].tap()
        app.sheets.buttons["Simulate start"].tap()
        XCTAssertTrue(app.staticTexts["Status, Running"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Spending"].tap()
        XCTAssertTrue(app.staticTexts["By project"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Instances"].tap()
        XCTAssertTrue(app.buttons["instance-stage"].waitForExistence(timeout: 3))
    }

    func testAccountExplainsExperimentWithoutStartingLogin() {
        let app = launch()
        app.buttons["accountButton"].tap()
        XCTAssertTrue(app.staticTexts["Login experiment"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["startLogin"].exists)
        XCTAssertTrue(app.staticTexts["No API keys created"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["spendingTotal"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBrowserLoginCanBeOpenedAndCancelled() {
        let app = launch()
        app.buttons["accountButton"].tap()
        app.buttons["startLogin"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if app.alerts.buttons["Continue"].waitForExistence(timeout: 2) {
            app.alerts.buttons["Continue"].tap()
        } else if springboard.alerts.buttons["Continue"].exists {
            springboard.alerts.buttons["Continue"].tap()
        }
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        _ = app.webViews.firstMatch.waitForExistence(timeout: 15)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Scaleway browser login — no credentials entered"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["loginCancelled"].waitForExistence(timeout: 5))
    }
}
