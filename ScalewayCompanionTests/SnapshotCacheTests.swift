// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

@MainActor
final class SnapshotCacheTests: XCTestCase {
    private let org = "11111111-1111-4111-8111-111111111111"
    private func isolatedCache() -> SnapshotCache { SnapshotCache(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")) }
    private let sample = WidgetSnapshot(organization: "o", organizationName: "Northwind", period: "2026-11",
                                        totals: [Money(currency: "EUR", amount: Decimal(string: "42.80")!)],
                                        forecasts: [Money(currency: "EUR", amount: 85)], running: 2, stopped: 1,
                                        updatedAt: Date(timeIntervalSince1970: 1_795_000_000))

    func testSnapshotIsStaleAfterUTCMonthChanges() {
        let iso = ISO8601DateFormatter()
        XCTAssertTrue(sample.isCurrentPeriod(now: iso.date(from: "2026-11-30T23:59:00Z")!))
        XCTAssertFalse(sample.isCurrentPeriod(now: iso.date(from: "2026-12-01T00:30:00Z")!))
        XCTAssertEqual(sample.currentForecasts(now: iso.date(from: "2026-11-20T00:00:00Z")!), sample.forecasts)
        XCTAssertEqual(sample.currentForecasts(now: iso.date(from: "2026-12-01T00:30:00Z")!), [])
    }
    func testRoundTrip() {
        let cache = isolatedCache()
        cache.save(sample)
        XCTAssertEqual(cache.load(), sample)
    }
    func testCorruptDataLoadsNil() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set(Data("not json".utf8), forKey: SnapshotCache.key)
        XCTAssertNil(SnapshotCache(defaults: defaults).load())
    }
    func testClearRemovesSnapshot() {
        let cache = isolatedCache()
        cache.save(sample); cache.clear()
        XCTAssertNil(cache.load())
    }
    func testMissingAppGroupIsANoOp() {
        let cache = SnapshotCache(defaults: nil)
        cache.save(sample)
        XCTAssertNil(cache.load())
    }
    func testStoreWritesSnapshotAfterRefreshWithoutSecrets() async throws {
        let cache = isolatedCache()
        let store = DashboardStore(api: RefinementService(), vault: MemoryVault(), cache: cache)
        await store.connect(secret: "fixture-secret", organization: org)
        let snapshot = try XCTUnwrap(cache.load())
        XCTAssertEqual(snapshot.organization, org)
        XCTAssertEqual(snapshot.totals, [Money(currency: "EUR", amount: Decimal(string: "42.80")!)])
        XCTAssertEqual(snapshot.running, 1)
        XCTAssertEqual(snapshot.stopped, 0)
        let raw = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(raw.contains("fixture-secret"))
        XCTAssertFalse(raw.contains("worker-01"))   // no Instance names
    }
    func testDisconnectAndReplacementClearSnapshot() async throws {
        let cache = isolatedCache()
        let store = DashboardStore(api: RefinementService(), vault: MemoryVault(), cache: cache)
        await store.connect(secret: "fixture", organization: org)
        XCTAssertNotNil(cache.load())
        try await store.adoptProvisionedConnection(APICredentials(secret: "new", organization: "22222222-2222-4222-8222-222222222222"))
        XCTAssertNil(cache.load())
        await store.refresh()
        XCTAssertNotNil(cache.load())
        await store.disconnect()
        XCTAssertNil(cache.load())
    }
    func testUnconnectedStoreWritesNothing() async {
        let cache = isolatedCache()
        let store = DashboardStore(api: RefinementService(), vault: MemoryVault(), cache: cache)
        await store.refresh()
        XCTAssertNil(cache.load())
    }
}
