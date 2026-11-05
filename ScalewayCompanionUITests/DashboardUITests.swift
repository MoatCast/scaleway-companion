// SPDX-License-Identifier: MPL-2.0

import XCTest

@MainActor
final class DashboardUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_IE"]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDashboardNavigationProjectFilteringAndDemoControls() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["spendingTotal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["spendingTotal"].label.contains("42.80"))
        capture(app, name: "overview-iphone")
        app.buttons["projectPicker"].tap()
        app.buttons["Personal"].tap()
        XCTAssertTrue(app.staticTexts["spendingTotal"].label.contains("6.00"))
        XCTAssertTrue(app.buttons["instance-stage"].exists)
        XCTAssertFalse(app.buttons["instance-api"].exists)
        app.buttons["instance-stage"].tap()
        XCTAssertEqual(app.staticTexts["instanceDetailName"].label, "staging")
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
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Spending"].tap()
        XCTAssertTrue(app.staticTexts["By project"].waitForExistence(timeout: 3))
        capture(app, name: "spending-iphone")
        app.buttons["projectPicker"].tap()
        app.buttons["All projects"].tap()
        XCTAssertTrue(app.staticTexts["Monthly history"].waitForExistence(timeout: 3))
        capture(app, name: "spending-history-iphone")
        app.tabBars.buttons["Instances"].tap()
        XCTAssertTrue(app.buttons["instance-stage"].waitForExistence(timeout: 3))
    }

    func testAutomaticSetupCanOpenAndReturnWithoutSigningIn() {
        let app = launch()
        app.buttons["accountButton"].tap()
        app.buttons["openAPIConnection"].tap()
        let entry = app.buttons["browserSetup"]
        if !entry.waitForExistence(timeout: 4) {
            XCTAssertTrue(app.buttons["accountButton"].waitForExistence(timeout: 8))
            app.buttons["accountButton"].tap()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: entry)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 30), .completed)
        entry.tap()
        XCTAssertTrue(app.buttons["automaticBrowserLogin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["approveReadOnlySetup"].exists)
        capture(app, name: "automatic-setup-before-sign-in-iphone")
        let manual = app.buttons["manualKeyFallback"]
        for _ in 0..<3 where !manual.isHittable { app.swipeUp() }
        XCTAssertTrue(manual.isHittable)
        manual.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    func testDemoCanOpenAPIConnectionForm() {
        let app = launch()
        app.buttons["accountButton"].tap()
        app.buttons["openAPIConnection"].tap()
        XCTAssertTrue(app.secureTextFields["apiSecret"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["organizationID"].exists)
        XCTAssertFalse(app.buttons["connectAPI"].isEnabled)
        XCTAssertFalse(app.buttons["startLogin"].exists)
        let explore = app.buttons["exploreDemo"]
        for _ in 0..<4 where !explore.isHittable { app.swipeUp() }
        XCTAssertTrue(explore.waitForExistence(timeout: 3))
        explore.tap()
        XCTAssertTrue(app.staticTexts["demoNotice"].waitForExistence(timeout: 5))
    }

    func testThemePersistsAcrossLaunchAndCanReturnToSystemAppearance() {
        let app = launch()
        app.buttons["accountButton"].tap()
        app.buttons["appearanceSettings"].tap()
        app.buttons["theme-forest"].tap()
        XCTAssertTrue(app.buttons["theme-forest"].isSelected)
        app.segmentedControls["appearanceMode"].buttons["Dark"].tap()
        capture(app, name: "appearance-forest-dark-iphone")
        app.terminate()
        app.launch()
        app.buttons["accountButton"].tap()
        app.buttons["appearanceSettings"].tap()
        XCTAssertTrue(app.buttons["theme-forest"].isSelected)
        XCTAssertTrue(app.segmentedControls["appearanceMode"].buttons["Dark"].isSelected)
        app.buttons["theme-ocean"].tap()
        app.segmentedControls["appearanceMode"].buttons["System"].tap()
    }

    func testInvalidConnectionShowsSafeErrorWithoutNetworkLogin() {
        let app = launch()
        app.buttons["accountButton"].tap()
        app.buttons["openAPIConnection"].tap()
        let secret = app.secureTextFields["apiSecret"]
        XCTAssertTrue(secret.waitForExistence(timeout: 5))
        secret.tap()
        secret.typeText("fixture")
        let organization = app.textFields["organizationID"]
        organization.tap()
        organization.typeText("invalid-organization")
        app.buttons["connectAPI"].tap()
        XCTAssertTrue(app.staticTexts["connectionError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["connectionError"].label.contains("fixture"))
    }
}
