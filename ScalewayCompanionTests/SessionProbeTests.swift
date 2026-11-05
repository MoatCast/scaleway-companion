// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

final class SessionProbeTests: XCTestCase {
    private let envelope = SessionEnvelope(token: "test.jwt.signature", jwt: .init(jti: "11111111-1111-4111-8111-111111111111", audienceId: "22222222-2222-4222-8222-222222222222"))
    func testMinimalReadUsesSessionOnlyAndValidatesBody() async throws {
        let probe = SessionProbe { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "api.scaleway.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Session-Token"), "test.jwt.signature")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Auth-Token"))
            XCTAssertNil(request.httpBody)
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertTrue(parts.queryItems!.contains(.init(name: "per_page", value: "1")))
            return (Data("{\"servers\":[]}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await probe.read(.instances, envelope: envelope, organization: envelope.jwt.audienceId)
        XCTAssertEqual(result, .verified)
    }
    func testDeniedMalformedAndRedirectedResponsesCannotPass() async throws {
        for (status, body, expected) in [(403, "{}", SessionProbe.Outcome.rejected(403)), (401, "{}", .rejected(401)), (302, "{}", .rejected(302)), (200, "{}", .invalidResponse)] {
            let probe = SessionProbe { request in
                (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            let result = try await probe.read(.spending, envelope: envelope, organization: envelope.jwt.audienceId)
            XCTAssertEqual(result, expected)
        }
        let probe = SessionProbe { _ in throw URLError(.notConnectedToInternet) }
        let outcome = try await probe.read(.spending, envelope: envelope, organization: envelope.jwt.audienceId)
        XCTAssertEqual(outcome, .network)
    }
    func testVerificationRejectsHTTPError() async throws {
        for status in [401, 403, 302] {
            do {
                _ = try await SessionVerifier.verify(envelope, transport: { request in
                    (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
                })
                XCTFail("Accepted HTTP \(status)")
            } catch { XCTAssertEqual(error as? LoginFailure, .rejected(status)) }
        }
    }
}
