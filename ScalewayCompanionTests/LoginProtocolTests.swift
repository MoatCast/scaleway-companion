// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import ScalewayCompanion

final class LoginProtocolTests: XCTestCase {
    private let jti = "11111111-1111-4111-8111-111111111111"
    private let audience = "22222222-2222-4222-8222-222222222222"

    private func callback(_ attempt: LoginAttempt, token: String = "header.payload.signature", id: String? = nil) throws -> URL {
        let object: [String: Any] = ["token": token, "renewToken": "ignored-secret", "jwt": ["jti": id ?? jti, "audienceId": audience]]
        let data = try JSONSerialization.data(withJSONObject: object)
        var url = URLComponents(url: attempt.callbackURL, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "token", value: data.base64EncodedString())]
        return url.url!
    }

    func testOfficialOriginAndRoundTripCallback() throws {
        let attempt = LoginAttempt(port: 34567)
        let url = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "account.scaleway.com")
        XCTAssertEqual(url.queryItems?.first?.value, attempt.callbackURL.absoluteString)
        let envelope = try attempt.decodeCallback(callback(attempt))
        let request = try SessionVerifier.verificationRequest(envelope)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.scaleway.com/iam/v1alpha1/jwts/\(jti)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Session-Token"), "header.payload.signature")
        XCTAssertNil(request.httpBody)
    }

    func testOldAttemptCannotCompleteNewLogin() throws {
        let first = LoginAttempt(port: 34567), second = LoginAttempt(port: 34567)
        XCTAssertThrowsError(try second.decodeCallback(callback(first))) { XCTAssertEqual($0 as? LoginFailure, .invalidCallback) }
    }

    func testRejectsWrongOriginAndFragments() throws {
        let attempt = LoginAttempt(port: 34567)
        let good = try callback(attempt)
        for replacement in ["http://evil:34567", "https://localhost:34567", "http://user@localhost:34567", "http://localhost:1234"] {
            let bad = URL(string: good.absoluteString.replacingOccurrences(of: "http://localhost:34567", with: replacement))!
            XCTAssertThrowsError(try attempt.decodeCallback(bad))
        }
        XCTAssertThrowsError(try attempt.decodeCallback(URL(string: good.absoluteString + "#token=other")!))
    }

    func testRejectsMalformedMissingDuplicateAndOversizedTokens() throws {
        let attempt = LoginAttempt(port: 34567)
        XCTAssertThrowsError(try attempt.decodeCallback(attempt.callbackURL))
        XCTAssertThrowsError(try attempt.decodeCallback(URL(string: attempt.callbackURL.absoluteString + "?token=not-base64")!))
        var duplicate = URLComponents(url: try callback(attempt), resolvingAgainstBaseURL: false)!
        duplicate.queryItems! += duplicate.queryItems!
        XCTAssertThrowsError(try attempt.decodeCallback(duplicate.url!))
        XCTAssertThrowsError(try attempt.decodeCallback(callback(attempt, token: String(repeating: "x", count: 33_000))))
    }

    func testRejectsHeaderAndPathInjection() throws {
        let attempt = LoginAttempt(port: 34567)
        XCTAssertThrowsError(try attempt.decodeCallback(callback(attempt, token: "secret\r\nX-Test: injected")))
        XCTAssertThrowsError(try attempt.decodeCallback(callback(attempt, id: "../../users")))
        XCTAssertThrowsError(try attempt.decodeCallback(callback(attempt, token: "")))
    }

    func testSessionMustMatchServerResponseAndBeUnexpired() throws {
        let attempt = LoginAttempt(port: 34567)
        let envelope = try attempt.decodeCallback(callback(attempt))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let valid = SessionVerification(jti: jti, audienceID: audience, expiresAt: "2030-01-01T00:00:00.123456Z")
        XCTAssertGreaterThan(try valid.validate(against: envelope, now: now), now)
        let expired = SessionVerification(jti: jti, audienceID: audience, expiresAt: "2020-01-01T00:00:00Z")
        XCTAssertThrowsError(try expired.validate(against: envelope, now: now)) { XCTAssertEqual($0 as? LoginFailure, .expired) }
        let other = SessionVerification(jti: UUID().uuidString, audienceID: audience, expiresAt: valid.expiresAt)
        XCTAssertThrowsError(try other.validate(against: envelope, now: now)) { XCTAssertEqual($0 as? LoginFailure, .mismatchedSession) }
        let invalid = SessionVerification(jti: jti, audienceID: audience, expiresAt: "tomorrow")
        XCTAssertThrowsError(try invalid.validate(against: envelope))
    }

    func testRedirectsDoNotForwardSessionCredentials() {
        let delegate = RejectRedirects()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://api.scaleway.com")!)
        let response = HTTPURLResponse(url: URL(string: "https://api.scaleway.com")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let request = URLRequest(url: URL(string: "https://unexpected.example")!)
        var called = false
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { result in
            called = true
            XCTAssertNil(result)
        }
        XCTAssertTrue(called)
    }

    func testProjectTotalsReconcileExactly() {
        let all = Spending.sample(for: .all)
        let production = Spending.sample(for: .production)
        let personal = Spending.sample(for: .personal)
        XCTAssertEqual(all.total, 4280)
        XCTAssertEqual(all.total, production.total + personal.total)
        XCTAssertEqual(all.compute, production.compute + personal.compute)
        XCTAssertEqual(all.storage, production.storage + personal.storage)
        XCTAssertEqual(all.network, production.network + personal.network)
    }
}

