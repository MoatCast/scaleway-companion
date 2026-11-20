// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

final class BudgetTests: XCTestCase {
    private let org = "11111111-1111-4111-8111-111111111111"
    private lazy var settings = BudgetSettings(enabled: true, amount: 200, currency: "EUR", organization: org)
    private func eur(_ amount: Decimal) -> [CurrencyAmount] { [CurrencyAmount(currency: "EUR", amount: amount)] }
    private func check(_ amount: Decimal, period: String = "2026-11", state: BudgetState?, settings custom: BudgetSettings? = nil,
                       totals: [CurrencyAmount]? = nil, organization: String? = nil) -> (alertPercent: Int?, state: BudgetState) {
        BudgetCheck.evaluate(settings: custom ?? settings, totals: totals ?? eur(amount), period: period, organization: organization ?? org, state: state)
    }

    func testThresholdsFireOncePerLevelWithinAMonth() {
        var result = check(158, state: nil)                 // 79 %
        XCTAssertNil(result.alertPercent)
        result = check(160, state: result.state)            // 80 %
        XCTAssertEqual(result.alertPercent, 80)
        result = check(190, state: result.state)            // 95 %, already told about 80
        XCTAssertNil(result.alertPercent)
        result = check(202, state: result.state)            // 101 %
        XCTAssertEqual(result.alertPercent, 100)
        result = check(240, state: result.state)            // 120 %
        XCTAssertNil(result.alertPercent)
    }
    func testNewMonthResetsNotifiedLevel() {
        let result = check(170, period: "2026-11", state: BudgetState(period: "2026-10", notifiedPercent: 100))
        XCTAssertEqual(result.alertPercent, 80)
        XCTAssertEqual(result.state, BudgetState(period: "2026-11", notifiedPercent: 80))
    }
    func testJumpPastBothThresholdsReportsHighest() {
        XCTAssertEqual(check(250, state: nil).alertPercent, 100)
    }
    func testOtherCurrencyIsIgnored() {
        XCTAssertNil(check(0, state: nil, totals: [CurrencyAmount(currency: "USD", amount: 500)]).alertPercent)
    }
    func testOtherOrganizationIsIgnored() {
        XCTAssertNil(check(500, state: nil, organization: "22222222-2222-4222-8222-222222222222").alertPercent)
    }
    func testDisabledOrNonPositiveBudgetNeverAlerts() {
        XCTAssertNil(check(500, state: nil, settings: BudgetSettings(enabled: false, amount: 200, currency: "EUR", organization: org)).alertPercent)
        XCTAssertNil(check(500, state: nil, settings: BudgetSettings(enabled: true, amount: 0, currency: "EUR", organization: org)).alertPercent)
    }
    @MainActor
    func testDisconnectAndReplacementClearBudget() async throws {
        let budget = BudgetStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let store = DashboardStore(api: RefinementService(), vault: MemoryVault(), cache: SnapshotCache(defaults: nil), budget: budget)
        await store.connect(secret: "fixture", organization: org)
        budget.settings = settings
        try await store.adoptProvisionedConnection(APICredentials(secret: "new", organization: "22222222-2222-4222-8222-222222222222"))
        XCTAssertNil(budget.settings)
        budget.settings = settings
        budget.state = BudgetState(period: "2026-11", notifiedPercent: 80)
        await store.disconnect()
        XCTAssertNil(budget.settings)
        XCTAssertNil(budget.state)
    }
    func testBudgetStorePersistsAndClears() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = BudgetStore(defaults: defaults)
        store.settings = settings
        store.state = BudgetState(period: "2026-11", notifiedPercent: 80)
        let reloaded = BudgetStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings, settings)
        XCTAssertEqual(reloaded.state?.notifiedPercent, 80)
        reloaded.clear()
        XCTAssertNil(BudgetStore(defaults: defaults).settings)
        XCTAssertNil(BudgetStore(defaults: defaults).state)
    }
}
