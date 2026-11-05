// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

@MainActor
final class AutomaticSetupTests: XCTestCase {
    let org = "11111111-1111-4111-8111-111111111111"
    let project = "22222222-2222-4222-8222-222222222222"
    func prepared(_ backend: SetupBackend, defaults: UserDefaults? = nil) async throws -> AutomaticSetup {
        let defaults = defaults ?? UserDefaults(suiteName: "setup-test-" + UUID().uuidString)!
        let setup = AutomaticSetup(api: IAMSetupAPI(transport: { try await backend.send($0) }), defaults: defaults, retryDelay: .zero)
        let envelope = SessionEnvelope(token: "fixture.jwt.signature", jwt: .init(jti: UUID().uuidString, audienceId: UUID().uuidString))
        await setup.prepare(.init(envelope: envelope, expiresAt: Date().addingTimeInterval(300)))
        await setup.selectOrganization(org)
        setup.toggleProject(project)
        return setup
    }
    func testMalformedRecoveryRecordDisablesNewSetupUntilExplicitlyCleared() async throws {
        let defaults = UserDefaults(suiteName: "setup-malformed-" + UUID().uuidString)!
        defaults.set(Data("malformed".utf8), forKey: "connection.pendingSetup")
        let setup = try await prepared(SetupBackend(), defaults: defaults)
        XCTAssertFalse(setup.canCreate)
        setup.clearRecoveryAfterManualCheck()
        XCTAssertTrue(setup.canCreate)
    }
    func testAllApplicationsPolicyCannotBroadenTheNewKey() async throws {
        let backend = SetupBackend(globalPolicy: true)
        let setup = try await prepared(backend)
        setup.create(store: DashboardStore(vault: MemoryVault()))
        while setup.busy { await Task.yield() }
        let keys = await backend.keysCreated
        XCTAssertEqual(keys, 0, "Inherited AllApps access must stop setup before key creation")
        XCTAssertNotEqual(setup.phase, .connected)
    }
    func testSessionExpiresEvenWhileRecoveryIsCleaning() async throws {
        let backend = SetupBackend(suspendCleanup: true)
        let defaults = UserDefaults(suiteName: "setup-expiry-" + UUID().uuidString)!
        defaults.set(try JSONEncoder().encode(SetupReceipt(organization: org)), forKey: "connection.pendingSetup")
        let setup = AutomaticSetup(api: IAMSetupAPI(transport: { try await backend.send($0) }), defaults: defaults)
        let envelope = SessionEnvelope(token: "fixture.jwt.signature", jwt: .init(jti: UUID().uuidString, audienceId: UUID().uuidString))
        await setup.prepare(.init(envelope: envelope, expiresAt: Date().addingTimeInterval(0.2)))
        let recovery = Task { await setup.recover(store: DashboardStore(vault: MemoryVault())) }
        await backend.waitForCleanup()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(setup.hasSession, "An expired broad session must leave coordinator memory even during recovery")
        await backend.resumeCleanup()
        await recovery.value
        XCTAssertFalse(setup.hasSession)
    }
    func testCancelDuringCreationRecordsReturnedIDBeforeRollback() async throws {
        let backend = SetupBackend(suspendApplication: true)
        let setup = try await prepared(backend)
        setup.create(store: DashboardStore(vault: MemoryVault()))
        await backend.waitForApplication()
        setup.cancel()
        await backend.resumeApplication()
        while setup.busy { await Task.yield() }
        XCTAssertEqual(setup.phase, .cancelled)
        let deleted = await backend.deleted
        let keys = await backend.keysCreated
        XCTAssertEqual(keys, 0)
        XCTAssertEqual(deleted, ["/iam/v1alpha1/applications/33333333-3333-4333-8333-333333333333"])
        XCTAssertNil(setup.pending)
    }
    func testPropagationRetriesAreBoundedAndDoNotCreateExtraKeys() async throws {
        let backend = SetupBackend(denyKeyReads: true)
        let setup = try await prepared(backend)
        setup.create(store: DashboardStore(vault: MemoryVault()))
        while setup.busy { await Task.yield() }
        let keys = await backend.keysCreated
        let reads = await backend.keyReads
        XCTAssertEqual(keys, 1)
        XCTAssertEqual(reads, 13)
        XCTAssertNil(setup.pending)
        XCTAssertNotEqual(setup.phase, .connected)
    }
    func testCleanupFailurePersistsRecoveryWithoutSessionOrKeyAndBlocksDuplicates() async throws {
        let backend = SetupBackend(failPolicy: true, failCleanup: true)
        let defaults = UserDefaults(suiteName: "setup-recovery-" + UUID().uuidString)!
        let setup = try await prepared(backend, defaults: defaults)
        let store = DashboardStore(vault: MemoryVault())
        setup.create(store: store)
        while setup.busy { await Task.yield() }
        XCTAssertTrue(setup.cleanupWarning)
        XCTAssertNotNil(setup.pending)
        let journal = try XCTUnwrap(defaults.data(forKey: "connection.pendingSetup"))
        let text = String(decoding: journal, as: UTF8.self)
        XCTAssertFalse(text.contains("fixture.jwt.signature"))
        XCTAssertFalse(text.contains("new-key"))
        let restored = AutomaticSetup(defaults: defaults)
        XCTAssertEqual(restored.pending, setup.pending)
        let writes = await backend.resourceWrites
        setup.create(store: store)
        let after = await backend.resourceWrites
        XCTAssertEqual(after, writes)
    }
    func testRecoveryDoesNotRevokeAlreadyCommittedConnection() async throws {
        let defaults = UserDefaults(suiteName: "setup-committed-" + UUID().uuidString)!
        let receipt = SetupReceipt(organization: org)
        defaults.set(try JSONEncoder().encode(receipt), forKey: "connection.pendingSetup")
        let vault = MemoryVault()
        let store = DashboardStore(api: PartialService(), vault: vault)
        try await store.adoptProvisionedConnection(APICredentials(secret: "committed-key", organization: org, setupName: receipt.name))
        let backend = SetupBackend()
        let setup = AutomaticSetup(api: IAMSetupAPI(transport: { try await backend.send($0) }), defaults: defaults)
        await setup.recover(store: store)
        XCTAssertNil(setup.pending)
        let deleted = await backend.deleted
        let saved = try await vault.load()
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(saved?.secret, "committed-key")
    }
    func testDiscoveryAndScopeSelectionNeverCreateResources() async throws {
        let backend = SetupBackend()
        let setup = try await prepared(backend)
        XCTAssertEqual(setup.selectedProjects, [project])
        let writes = await backend.resourceWrites
        XCTAssertEqual(writes, 0)
    }
    func testApplicationKeyIsSavedOnlyAfterVerification() async throws {
        let backend = SetupBackend()
        let setup = try await prepared(backend)
        let vault = MemoryVault()
        let store = DashboardStore(api: PartialService(), vault: vault)
        await store.connect(secret: "old-key", organization: org)
        setup.create(store: store)
        while setup.busy { await Task.yield() }
        XCTAssertEqual(setup.phase, .connected)
        let saved = try await vault.load()
        XCTAssertEqual(saved?.secret, "new-key")
        XCTAssertNotNil(saved?.setupName)
        XCTAssertNil(setup.pending)
    }
    func testKeychainFailureRollsBackOnlyAttemptAndPreservesOldKey() async throws {
        let backend = SetupBackend()
        let setup = try await prepared(backend)
        let vault = FailingReplacementVault()
        let store = DashboardStore(api: PartialService(), vault: vault)
        await store.connect(secret: "old-key", organization: org)
        setup.create(store: store)
        while setup.busy { await Task.yield() }
        let saved = await vault.load()
        XCTAssertEqual(saved?.secret, "old-key")
        XCTAssertEqual(store.organization, org)
        let deleted = await backend.deleted
        XCTAssertEqual(deleted, ["/iam/v1alpha1/policies/44444444-4444-4444-8444-444444444444", "/iam/v1alpha1/applications/33333333-3333-4333-8333-333333333333"])
        XCTAssertNil(setup.pending)
    }
    func testPolicyDenialRemovesApplicationAndNeverCreatesKey() async throws {
        let backend = SetupBackend(failPolicy: true)
        let setup = try await prepared(backend)
        setup.create(store: DashboardStore(vault: MemoryVault()))
        while setup.busy { await Task.yield() }
        let keys = await backend.keysCreated
        let deleted = await backend.deleted
        XCTAssertEqual(keys, 0)
        XCTAssertEqual(deleted, ["/iam/v1alpha1/applications/33333333-3333-4333-8333-333333333333"])
        XCTAssertNil(setup.pending)
    }
}

actor SetupBackend {
    let org = "11111111-1111-4111-8111-111111111111"
    let project = "22222222-2222-4222-8222-222222222222"
    let app = "33333333-3333-4333-8333-333333333333"
    let policy = "44444444-4444-4444-8444-444444444444"
    var name = ""
    var applicationCreated = false
    var policyCreated = false
    var resourceWrites = 0
    var keysCreated = 0
    var deleted: [String] = []
    let failPolicy: Bool
    let failCleanup: Bool
    let denyKeyReads: Bool
    let suspendApplication: Bool
    let globalPolicy: Bool
    let suspendCleanup: Bool
    private var cleanupWaiter: CheckedContinuation<Void, Never>?
    private var cleanupWaiting = false
    var keyReads = 0
    private var applicationWaiter: CheckedContinuation<Void, Never>?
    private var applicationWaiting = false
    init(failPolicy: Bool = false, failCleanup: Bool = false, denyKeyReads: Bool = false, suspendApplication: Bool = false, globalPolicy: Bool = false, suspendCleanup: Bool = false) {
        self.failPolicy = failPolicy; self.failCleanup = failCleanup; self.denyKeyReads = denyKeyReads; self.suspendApplication = suspendApplication
        self.globalPolicy = globalPolicy; self.suspendCleanup = suspendCleanup
    }
    func waitForCleanup() async { while !cleanupWaiting { await Task.yield() } }
    func resumeCleanup() { cleanupWaiter?.resume(); cleanupWaiter = nil }
    func waitForApplication() async { while !applicationWaiting { await Task.yield() } }
    func resumeApplication() { applicationWaiter?.resume(); applicationWaiter = nil }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let appJSON: [String: Any] = ["id": app, "organization_id": org, "name": name]
        let policyJSON: [String: Any] = ["id": policy, "organization_id": org, "name": name, "application_id": app]
        var json: [String: Any] = [:]
        var code = 200
        switch (request.httpMethod!, path) {
        case ("GET", let path) where path.hasSuffix("/connections"):
            json = ["connections": [["organization": ["id": org, "name": "Example", "locked": false]]]]
        case ("GET", "/account/v3/projects"):
            json = ["projects": [["id": project, "name": "Example project", "organization_id": org]], "total_count": 1]
        case ("POST", "/iam/v1alpha1/check-permissions"):
            json = ["responses": (body["permissions"] as! [[String: String]]).map { _ in ["decision": "allow"] }]
        case ("POST", "/iam/v1alpha1/applications"):
            resourceWrites += 1; name = body["name"] as! String; applicationCreated = true
            json = ["id": app, "organization_id": org, "name": name]
            if suspendApplication { await withCheckedContinuation { applicationWaiter = $0; applicationWaiting = true } }
        case ("POST", "/iam/v1alpha1/policies"):
            resourceWrites += 1
            if failPolicy { code = 403 } else { policyCreated = true; json = policyJSON }
        case ("POST", "/iam/v1alpha1/api-keys"):
            resourceWrites += 1; keysCreated += 1
            json = ["application_id": app, "secret_key": "new-key", "access_key": "SCWfixture123"]
        case ("GET", "/iam/v1alpha1/policies/" + policy): json = policyJSON
        case ("GET", "/iam/v1alpha1/rules"):
            json = ["rules": [["permission_set_names": ["InstancesReadOnly"], "project_ids": [project]], ["permission_set_names": ["BillingReadOnly"], "organization_id": org]], "total_count": 2]
        case ("GET", "/iam/v1alpha1/policies"):
            if suspendCleanup { await withCheckedContinuation { cleanupWaiter = $0; cleanupWaiting = true } }
            var policies = policyCreated ? [policyJSON] : []
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            if globalPolicy && !query.contains(where: { $0.name == "policy_name" }) {
                policies.append(["id": "55555555-5555-4555-8555-555555555555", "organization_id": org, "name": "All apps broad access", "group_id": "66666666-6666-4666-8666-666666666666"])
            }
            json = ["policies": policies, "total_count": policies.count]
        case ("GET", "/iam/v1alpha1/groups"):
            let groups: [[String: Any]] = globalPolicy ? [["id": "66666666-6666-4666-8666-666666666666", "organization_id": org, "application_ids": [], "all_applications": true]] : []
            json = ["groups": groups, "total_count": groups.count]
        case ("GET", "/iam/v1alpha1/applications/" + app): json = appJSON
        case ("GET", "/iam/v1alpha1/applications"):
            json = ["applications": applicationCreated ? [appJSON] : [], "total_count": applicationCreated ? 1 : 0]
        case ("GET", let path) where path.hasSuffix("/servers"):
            keyReads += 1; json = ["servers": []]; if denyKeyReads { code = 403 }
        case ("GET", "/billing/v2beta1/consumptions"): json = ["consumptions": []]
        case ("DELETE", _): deleted.append(path); if failCleanup { code = 403 }
        default: throw SetupFailure.invalidResponse
        }
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}
