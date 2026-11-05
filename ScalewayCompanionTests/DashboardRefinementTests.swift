// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

@MainActor
final class DashboardRefinementTests: XCTestCase {
    let org = "11111111-1111-4111-8111-111111111111"

    func testAllZonesIncludeMilanAndPartialFailuresAreExplicit() async {
        let api = RefinementService()
        let store = DashboardStore(api: api, vault: MemoryVault())
        await store.connect(secret: "fixture", organization: org)
        XCTAssertEqual(CloudAPI.zones.count, 12)
        XCTAssertTrue(CloudAPI.zones.contains("it-mil-1"))
        XCTAssertEqual(store.zone, "")
        XCTAssertEqual(store.successfulZones.count, 11)
        XCTAssertNotNil(store.failedZones["nl-ams-2"])
        XCTAssertEqual(store.instances.map(\.zone), ["it-mil-1"])
        let peak = await api.peak
        XCTAssertLessThanOrEqual(peak, 3)
        store.search = "worker"
        XCTAssertEqual(store.visibleInstances.count, 1)
        store.statusFilter = "stopped"
        XCTAssertTrue(store.visibleInstances.isEmpty)
        store.statusFilter = ""
        await store.selectZone("fr-par-1")
        XCTAssertTrue(store.visibleInstances.isEmpty)
    }

    func testFailedRefreshKeepsPreviousValuesMarkedStale() async {
        let api = RefinementService()
        let store = DashboardStore(api: api, vault: MemoryVault())
        await store.connect(secret: "fixture", organization: org)
        let stamp = store.zoneUpdatedAt["it-mil-1"]
        let billingStamp = store.spendingFetchedAt
        XCTAssertNotNil(store.spending)
        await api.failEverything()
        await store.refresh()
        XCTAssertEqual(store.instances.count, 1)
        XCTAssertTrue(store.isZoneStale("it-mil-1"))
        XCTAssertEqual(store.zoneUpdatedAt["it-mil-1"], stamp)
        XCTAssertNotNil(store.spending)
        XCTAssertNotNil(store.spendingError)
        XCTAssertEqual(store.spendingFetchedAt, billingStamp)
    }

    func testHistoryKeepsFailureAsMissingAndDoesNotMixCurrency() async {
        let now = Date(timeIntervalSince1970: 1793786400)
        let store = DashboardStore(api: RefinementService(), vault: MemoryVault(), now: { now })
        await store.connect(secret: "fixture", organization: org)
        await store.loadHistory()
        XCTAssertEqual(store.periods.count, 6)
        XCTAssertNotNil(store.historyErrors["2026-09"])
        let euros = store.historyPoints(currency: "EUR")
        XCTAssertNil(euros.first { $0.period == "2026-09" }?.amount)
        XCTAssertNil(euros.first { $0.period == "2026-08" }?.amount)
        XCTAssertEqual(euros.last?.amount, Decimal(string: "42.80"))
        await store.disconnect()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(store.historyErrors.isEmpty)
    }

    func testHistoryRetryRecoversCachedCurrentMonthAfterFailedRefresh() async {
        let api = RefinementService()
        let now = Date(timeIntervalSince1970: 1793786400)
        let store = DashboardStore(api: api, vault: MemoryVault(), now: { now })
        await store.connect(secret: "fixture", organization: org)
        await api.failEverything()
        await store.refresh()
        XCTAssertNotNil(store.spendingError)
        await api.recover()
        await store.loadHistory(force: true)
        XCTAssertNil(store.historyErrors["2026-11"])
        XCTAssertNil(store.spendingError)
    }

    func testCancelledHistoryDoesNotCreateNetworkErrors() async {
        let service = SuspendedHistoryService()
        let now = Date(timeIntervalSince1970: 1793786400)
        let store = DashboardStore(api: service, vault: MemoryVault(), now: { now })
        await store.connect(secret: "fixture", organization: org)
        let task = Task { await store.loadHistory() }
        await service.waitUntilStarted()
        task.cancel()
        await service.resume()
        await task.value
        XCTAssertFalse(store.historyBusy)
        XCTAssertNil(store.historyErrors["2026-06"])
    }

    func testDisconnectedAccountCannotReceiveLateHistory() async {
        let service = SuspendedHistoryService()
        let now = Date(timeIntervalSince1970: 1793786400)
        let store = DashboardStore(api: service, vault: MemoryVault(), now: { now })
        await store.connect(secret: "fixture", organization: org)
        let task = Task { await store.loadHistory() }
        await service.waitUntilStarted()
        await store.disconnect()
        await service.resume()
        await task.value
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(store.historyErrors.isEmpty)
    }

    func testOverviewFleetIgnoresHiddenListFilters() async {
        let store = DashboardStore(api: RefinementService(), vault: MemoryVault())
        await store.connect(secret: "fixture", organization: org)
        store.search = "does-not-exist"
        store.statusFilter = "stopped"
        await store.selectZone("fr-par-1")
        XCTAssertTrue(store.visibleInstances.isEmpty)
        XCTAssertEqual(store.projectInstances.count, 1)
    }

    func testPeriodsCrossYearBoundaryInUTC() {
        let now = ISO8601DateFormatter().date(from: "2027-01-01T00:01:00Z")!
        XCTAssertEqual(DashboardStore.billingPeriods(now: now), ["2026-08","2026-09","2026-10","2026-11","2026-12","2027-01"])
    }

    func testCurrencyMinorUnitsMatchDisplayedPrecision() throws {
        for (currency, nanos, expected) in [("JPY", 490000000, "0"), ("BHD", 105000000, "0.210")] {
            let json = "[{\"value\":{\"currency_code\":\"\(currency)\",\"units\":0,\"nanos\":\(nanos)},\"project_id\":\"p\",\"category_name\":\"Compute\"},{\"value\":{\"currency_code\":\"\(currency)\",\"units\":0,\"nanos\":\(nanos)},\"project_id\":\"p\",\"category_name\":\"Storage\"}]"
            let items = try JSONDecoder().decode([Consumption].self, from: Data(json.utf8))
            XCTAssertEqual(BillingSummary.totals(items).first?.amount, Decimal(string: expected))
        }
    }

    func testDisplayedCategoryTotalsReconcileWithoutMixingCurrency() throws {
        let json = #"[{"value":{"currency_code":"EUR","units":0,"nanos":105000000},"project_id":"p","category_name":"Compute"},{"value":{"currency_code":"EUR","units":0,"nanos":105000000},"project_id":"p","category_name":"Storage"},{"value":{"currency_code":"USD","units":3,"nanos":0},"project_id":"p","category_name":"Compute"}]"#
        let items = try JSONDecoder().decode([Consumption].self, from: Data(json.utf8))
        let totals = BillingSummary.totals(items)
        XCTAssertEqual(totals.first { $0.currency == "EUR" }?.amount, Decimal(string: "0.22"))
        XCTAssertEqual(totals.first { $0.currency == "USD" }?.amount, 3)
        XCTAssertEqual(BillingSummary.totals(items, project: "other").count, 0)
    }
}

actor RefinementService: CloudService {
    var failing = false
    var active = 0
    var peak = 0
    func failEverything() { failing = true }
    func recover() { failing = false }
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance] {
        active += 1; peak = max(peak, active)
        defer { active -= 1 }
        await Task.yield()
        if failing || zone == "nl-ams-2" { throw APIError.network }
        return zone == "it-mil-1" ? [LiveInstance(id:"worker", name:"worker-01", project:"p", type:"DEV1-S", state:"running")] : []
    }
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot {
        if failing || period == "2026-09" { throw APIError.forbidden }
        let currency = period == "2026-08" ? "USD" : "EUR"
        let json = "[{\"value\":{\"currency_code\":\"\(currency)\",\"units\":42,\"nanos\":800000000},\"project_id\":\"p\",\"category_name\":\"Compute\"}]"
        return SpendingSnapshot(items: try JSONDecoder().decode([Consumption].self, from: Data(json.utf8)), updatedAt: nil, period: period)
    }
}

actor SuspendedHistoryService: CloudService {
    var started = false
    var continuation: CheckedContinuation<Void, Never>?
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance] { [] }
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot {
        if period == "2026-06" {
            await withCheckedContinuation { continuation = $0; started = true }
        }
        try Task.checkCancellation()
        return SpendingSnapshot(items: [], updatedAt: nil, period: period)
    }
    func waitUntilStarted() async { while !started { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
}
