// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

final class AppearancePreferencesTests: XCTestCase {
    func testUnknownSavedChoicesUseOceanAndSystem() {
        XCTAssertEqual(AppTheme(storedValue: "removed-theme"), .ocean)
        XCTAssertEqual(AppAppearance(storedValue: "removed-mode"), .system)
    }

    func testEveryChoiceRoundTripsAndHasLightAndDarkAccents() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(AppTheme(storedValue: theme.rawValue), theme)
            XCTAssertNotEqual(theme.lightAccent, theme.darkAccent)
        }
        for appearance in AppAppearance.allCases {
            XCTAssertEqual(AppAppearance(storedValue: appearance.rawValue), appearance)
        }
        XCTAssertEqual(AppTheme.ocean.lightAccent, 0x1B6C80)
        XCTAssertEqual(AppTheme.ocean.darkAccent, 0x65AEBF)
    }
}
