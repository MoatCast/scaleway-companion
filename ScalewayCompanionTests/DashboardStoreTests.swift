// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

@MainActor
final class DashboardStoreTests: XCTestCase {
    let organization = "11111111-1111-4111-8111-111111111111"

    func testCancellationAndDisconnectCannotInterruptKeychainCommit() async throws {
        let vault = DelayedReplacementVault()
        let store = DashboardStore(api: PartialService(), vault: vault)
        await store.connect(secret: "old-key", organization: organization)
        let next = try APICredentials(secret: "new-key", organization: "22222222-2222-4222-8222-222222222222")
        let commit = Task { try await store.adoptProvisionedConnection(next) }
        await vault.waitUntilSaving()
        await store.disconnect()
        commit.cancel()
        await vault.resume()
        try await commit.value
        XCTAssertTrue(store.connected)
        XCTAssertEqual(store.organization, next.organization)
        let saved = try await vault.load()
        XCTAssertEqual(saved?.secret, "new-key")
        XCTAssertFalse(store.busy)
    }
    func testVerifiedReplacementClearsOldAccountOnlyAfterSave() async throws {
        let vault = MemoryVault()
        let store = DashboardStore(api: PartialService(), vault: vault)
        await store.connect(secret: "old-key", organization: organization)
        let candidate = try APICredentials(secret: "new-key", organization: "22222222-2222-4222-8222-222222222222", setupName: "attempt")
        try await store.adoptProvisionedConnection(candidate)
        XCTAssertEqual(store.organization, candidate.organization)
        XCTAssertEqual(store.setupName, "attempt")
        XCTAssertTrue(store.instances.isEmpty)
        XCTAssertNil(store.spending)
        let saved = try await vault.load()
        XCTAssertEqual(saved?.secret, "new-key")
        XCTAssertEqual(saved?.setupName, "attempt")
    }
    func testFailedReplacementPreservesExistingKeyAndData() async throws {
        let vault = FailingReplacementVault()
        let store = DashboardStore(api: PartialService(), vault: vault)
        await store.connect(secret: "old-key", organization: organization)
        do {
            try await store.adoptProvisionedConnection(APICredentials(secret: "new-key", organization: UUID().uuidString))
            XCTFail("Expected save failure")
        } catch { }
        XCTAssertEqual(store.organization, organization)
        XCTAssertEqual(store.instances.count, 1)
        let saved = try await vault.load()
        XCTAssertEqual(saved?.secret, "old-key")
    }
    func testPartialPermissionFailureStillConnectsAndDisconnectClearsEverything() async throws {
        let vault = MemoryVault()
        let store = DashboardStore(api: PartialService(), vault: vault)
        await store.connect(secret: "fixture", organization: organization)
        XCTAssertTrue(store.connected)
        XCTAssertEqual(store.instances.count, 1)
        XCTAssertEqual(store.spendingError, APIError.forbidden.localizedDescription)
        XCTAssertNil(store.spending)
        let saved = try await vault.load()
        XCTAssertNotNil(saved)
        await store.disconnect()
        XCTAssertFalse(store.connected)
        XCTAssertTrue(store.instances.isEmpty)
        XCTAssertNil(store.spending)
        let removed = try await vault.load()
        XCTAssertNil(removed)
    }

    func testRejectedKeyIsNotPersistedOrReportedAsConnected() async {
        let vault = MemoryVault()
        let store = DashboardStore(api: RejectedService(), vault: vault)
        await store.connect(secret: "fixture", organization: organization)
        XCTAssertFalse(store.connected)
        XCTAssertNotNil(store.connectionError)
        let saved = try? await vault.load()
        XCTAssertNil(saved)
    }

    func testDisconnectFailureIsVisibleAndKeepsConnectionForRetry() async {
        let vault = MemoryVault(failDelete: true)
        let store = DashboardStore(api: PartialService(), vault: vault)
        await store.connect(secret: "fixture", organization: organization)
        await store.disconnect()
        XCTAssertTrue(store.connected)
        XCTAssertEqual(store.connectionError, APIError.keychain.localizedDescription)
    }

    func testDisconnectDuringRefreshRejectsLateAccountData() async {
        let service = SuspendedService()
        let store = DashboardStore(api: service, vault: MemoryVault())
        let task = Task { await store.connect(secret: "fixture", organization: organization) }
        await service.waitUntilStarted()
        await store.disconnect()
        await service.resume()
        await task.value
        XCTAssertFalse(store.connected)
        XCTAssertTrue(store.instances.isEmpty)
    }
}

actor MemoryVault: CredentialVault {
    var value: APICredentials?
    let failDelete: Bool
    init(failDelete: Bool = false) { self.failDelete = failDelete }
    func load() throws -> APICredentials? { value }
    func save(_ credentials: APICredentials) throws { value = credentials }
    func delete() throws { if failDelete { throw APIError.keychain }; value = nil }
}
struct PartialService: CloudService {
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance] {
        zone == "fr-par-1" ? [LiveInstance(id: "example", name: "Example", project: "p1", type: "DEV1-S", state: "running")] : []
    }
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot { throw APIError.forbidden }
}
struct RejectedService: CloudService {
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance] { throw APIError.invalidKey }
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot { throw APIError.invalidKey }
}
actor SuspendedService: CloudService {
    var continuation: CheckedContinuation<Void, Never>?
    var started = false
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance] {
        guard zone == "fr-par-1" else { return [] }
        await withCheckedContinuation { continuation = $0; started = true }
        return try await PartialService().instances(credentials: credentials, zone: zone)
    }
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot { throw APIError.forbidden }
    func waitUntilStarted() async { while !started { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
}

actor FailingReplacementVault: CredentialVault {
    var value: APICredentials?
    func load() -> APICredentials? { value }
    func save(_ credentials: APICredentials) throws {
        if value != nil { throw APIError.keychain }
        value = credentials
    }
    func delete() { value = nil }
}

actor DelayedReplacementVault: CredentialVault {
    var value: APICredentials?
    var continuation: CheckedContinuation<Void, Never>?
    var waiting = false
    func load() -> APICredentials? { value }
    func save(_ credentials: APICredentials) async {
        if value != nil { await withCheckedContinuation { continuation = $0; waiting = true } }
        value = credentials
    }
    func delete() { value = nil }
    func waitUntilSaving() async { while !waiting { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
}
