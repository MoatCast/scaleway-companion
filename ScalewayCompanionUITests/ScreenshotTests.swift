// SPDX-License-Identifier: MPL-2.0
import XCTest

/// App Store screenshots from demo mode (sample data only). Run on a 6.9" simulator with
/// `xcrun simctl status_bar <id> override --time 9:41 ...`, then export the attachments.
@MainActor
final class ScreenshotTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAppStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_IE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["spendingTotal"].waitForExistence(timeout: 10))
        shot(app, "01-overview")

        app.tabBars.buttons["Spending"].tap()
        XCTAssertTrue(app.staticTexts["Monthly history"].waitForExistence(timeout: 5))
        shot(app, "02-spending")

        app.tabBars.buttons["Instances"].tap()
        XCTAssertTrue(app.buttons["instance-api"].waitForExistence(timeout: 5))
        shot(app, "03-instances")

        app.buttons["instance-api"].tap()
        XCTAssertTrue(app.staticTexts["instanceDetailName"].waitForExistence(timeout: 5))
        shot(app, "04-instance-detail")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["accountButton"].tap()
        app.buttons["appearanceSettings"].tap()
        XCTAssertTrue(app.buttons["theme-ocean"].waitForExistence(timeout: 5))
        shot(app, "05-appearance")
    }
}
