// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

final class IAMSetupTests: XCTestCase {
    let org = "11111111-1111-4111-8111-111111111111"
    let project = "22222222-2222-4222-8222-222222222222"
    let app = "33333333-3333-4333-8333-333333333333"
    var session: SetupSession {
        .init(envelope: .init(token: "fixture.jwt.signature", jwt: .init(jti: UUID().uuidString, audienceId: UUID().uuidString)), expiresAt: Date().addingTimeInterval(300))
    }
    func testPolicyCannotGrantInstancesOutsideSelectedProjectsOrCreateUserKey() async throws {
        let fixture = FixtureTransport(responses: [("{\"id\":\"44444444-4444-4444-8444-444444444444\",\"organization_id\":\"\(org)\",\"name\":\"test\",\"application_id\":\"\(app)\"}", [:], 200), ("{\"application_id\":\"\(app)\",\"secret_key\":\"fixture-key\",\"access_key\":\"SCWfixture123\",\"user_id\":null}", [:], 200)])
        let api = IAMSetupAPI(transport: { try await fixture.send($0) })
        _ = try await api.createPolicy(session: session, organization: org, projects: [project], application: app, name: "test")
        _ = try await api.createKey(session: session, application: app, name: "test")
        let requests = await fixture.requests
        let policy = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        let rules = try XCTUnwrap(policy["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0]["permission_set_names"] as? [String], ["InstancesReadOnly"])
        XCTAssertEqual(rules[0]["project_ids"] as? [String], [project])
        XCTAssertNil(rules[0]["organization_id"])
        XCTAssertEqual(rules[1]["permission_set_names"] as? [String], ["BillingReadOnly"])
        XCTAssertEqual(rules[1]["organization_id"] as? String, org)
        XCTAssertNil(policy["user_id"])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "api.scaleway.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Session-Token"), "fixture.jwt.signature")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Auth-Token"))
            XCTAssertNil((try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])?["user_id"])
        }
    }
    func testUnacknowledgedCreationIsNotReportedCleanFromEmptyListings() async throws {
        var receipt = SetupReceipt(organization: org)
        receipt.uncertain = true
        let fixture = FixtureTransport(responses: [("{\"policies\":[],\"total_count\":0}", [:], 200), ("{\"applications\":[],\"total_count\":0}", [:], 200)])
        let api = IAMSetupAPI(transport: { try await fixture.send($0) })
        let clean = await api.cleanup(session: session, receipt: receipt)
        XCTAssertFalse(clean)
    }
    func testKnownResourceRenamedOutOfListIsNotReportedClean() async throws {
        var receipt = SetupReceipt(organization: org)
        receipt.application = app
        let api = IAMSetupAPI { request in
            let json = request.url!.path.hasSuffix("33333333-3333-4333-8333-333333333333")
                ? "{\"id\":\"33333333-3333-4333-8333-333333333333\",\"organization_id\":\"11111111-1111-4111-8111-111111111111\",\"name\":\"renamed-by-owner\"}"
                : "{\"policies\":[],\"applications\":[],\"total_count\":0}"
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let clean = await api.cleanup(session: session, receipt: receipt)
        XCTAssertFalse(clean, "Stored resource ID must be checked even when name lists are empty")
    }
    func testForeignOrganizationProjectsAndPrematureEmptyPaginationAreRejected() async throws {
        for json in ["{\"projects\":[{\"id\":\"\(project)\",\"name\":\"foreign\",\"organization_id\":\"\(app)\"}],\"total_count\":1}", "{\"projects\":[],\"total_count\":1}"] {
            let fixture = FixtureTransport(responses: [(json, [:], 200)])
            let api = IAMSetupAPI(transport: { try await fixture.send($0) })
            do { _ = try await api.projects(session: session, organization: org); XCTFail("Foreign or incomplete project list accepted") } catch { }
        }
    }
    func testUnexpectedUserBoundKeyIsNeverAccepted() async throws {
        let json = "{\"application_id\":\"\(app)\",\"secret_key\":\"fixture-key\",\"access_key\":\"SCWfixture123\",\"user_id\":\"\(org)\"}"
        let fixture = FixtureTransport(responses: [(json, [:], 200)])
        let api = IAMSetupAPI(transport: { try await fixture.send($0) })
        do { _ = try await api.createKey(session: session, application: app, name: "test"); XCTFail("User key accepted") } catch { }
    }
    func testRedirectedResponseCannotBeAcceptedEvenWithValidJSON() async throws {
        let api = IAMSetupAPI { request in
            (Data("{\"connections\":[]}".utf8), HTTPURLResponse(url: URL(string: "https://unexpected.example")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await api.organizations(session: session); XCTFail("Foreign origin accepted") }
        catch { XCTAssertEqual(error as? SetupFailure, .invalidResponse) }
    }
    func testPolicyReadbackRejectsOrganizationWideInstanceScope() async throws {
        var receipt = SetupReceipt(organization: org)
        receipt.application = app; receipt.policy = "44444444-4444-4444-8444-444444444444"
        let policy = "{\"id\":\"\(receipt.policy!)\",\"organization_id\":\"\(org)\",\"name\":\"\(receipt.name)\",\"application_id\":\"\(app)\"}"
        let broadRules = "{\"rules\":[{\"permission_set_names\":[\"InstancesReadOnly\"],\"organization_id\":\"\(org)\"},{\"permission_set_names\":[\"BillingReadOnly\"],\"organization_id\":\"\(org)\"}],\"total_count\":2}"
        let fixture = FixtureTransport(responses: [(policy, [:], 200), (broadRules, [:], 200)])
        let api = IAMSetupAPI(transport: { try await fixture.send($0) })
        do { try await api.verifyPolicy(session: session, receipt: receipt, projects: [project]); XCTFail("Broadened scope accepted") }
        catch { XCTAssertEqual(error as? SetupFailure, .verification) }
    }
    func testEmptyOrWildcardProjectSelectionMakesNoRequest() async throws {
        let fixture = FixtureTransport(responses: [])
        let api = IAMSetupAPI(transport: { try await fixture.send($0) })
        for projects in [[], ["*"], [project, project]] {
            do { _ = try await api.createPolicy(session: session, organization: org, projects: projects, application: app, name: "test"); XCTFail("Invalid selection accepted") } catch { }
        }
        let count = await fixture.requestCount()
        XCTAssertEqual(count, 0)
    }
    func testDeniedPreflightAndMalformedPermissionResponseFailClosed() async throws {
        for json in ["{\"responses\":[]}", "{\"responses\":[{\"decision\":\"deny\"}]}"] {
            let fixture = FixtureTransport(responses: [(json, [:], 200)])
            let api = IAMSetupAPI(transport: { try await fixture.send($0) })
            do { try await api.preflight(session: session, organization: org); XCTFail("Missing permission accepted") } catch { }
        }
    }
    func testExpiredSessionNeverSendsCredentials() async throws {
        let fixture = FixtureTransport(responses: [])
        let api = IAMSetupAPI(transport: { try await fixture.send($0) })
        let expired = SetupSession(envelope: session.envelope, expiresAt: .distantPast)
        do { _ = try await api.organizations(session: expired); XCTFail("Expired session accepted") } catch { }
        let count = await fixture.requestCount()
        XCTAssertEqual(count, 0)
    }
}
