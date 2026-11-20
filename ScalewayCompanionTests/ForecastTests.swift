// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

final class ForecastTests: XCTestCase {
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    func testLinearProjectionMidMonth() {   // November 2026 has 30 days; 15 days elapsed
        XCTAssertEqual(Forecast.monthEnd(total: 15, currency: "EUR", period: "2026-11", now: date("2026-11-16T00:00:00Z")), 30)
    }
    func testHiddenDuringFirstThreeDays() {
        XCTAssertNil(Forecast.monthEnd(total: 5, currency: "EUR", period: "2026-11", now: date("2026-11-03T23:59:00Z")))
    }
    func testHiddenForPastPeriod() {
        XCTAssertNil(Forecast.monthEnd(total: 5, currency: "EUR", period: "2026-10", now: date("2026-11-16T00:00:00Z")))
    }
    func testRoundsToCurrencyPrecision() {   // JPY has 0 decimals; 100 / 7 days × 30 = 428.57
        XCTAssertEqual(Forecast.monthEnd(total: 100, currency: "JPY", period: "2026-11", now: date("2026-11-08T00:00:00Z")), 429)
    }
    func testMonthBoundaryUsesUTC() {   // 00:30 UTC on 1 Dec is December, so November is already a past period
        XCTAssertNil(Forecast.monthEnd(total: 50, currency: "EUR", period: "2026-11", now: date("2026-12-01T00:30:00Z")))
    }
}
