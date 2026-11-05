// SPDX-License-Identifier: MPL-2.0

import Foundation

enum LoginFailure: Error, LocalizedError, Equatable {
    case invalidCallback, invalidToken, invalidResponse, rejected(Int), mismatchedSession, expired, timedOut, listenerUnavailable

    var errorDescription: String? {
        switch self {
        case .timedOut: "No completed callback after three minutes. Scaleway may have rejected the redirect, or sign-in may be incomplete."
        case .listenerUnavailable: "The private callback receiver could not start on this device."
        case .invalidCallback: "The callback did not match this sign-in attempt. No session was accepted."
        case .invalidToken: "Scaleway returned an unexpected token format. No session was accepted."
        case .invalidResponse: "Scaleway returned an unexpected verification response."
        case .rejected(let status): "The callback arrived, but Scaleway could not verify the session (HTTP \(status)). This can also indicate missing IAM permissions."
        case .mismatchedSession: "The returned session did not match Scaleway’s verification response."
        case .expired: "The session has expired. Start a new sign-in attempt."
        }
    }
}

struct LoginAttempt {
    static let scheme = "scalewaycompanion"
    let id: UUID
    let port: UInt16

    init(port: UInt16, id: UUID = UUID()) { self.port = port; self.id = id }

    // The nonce correlates a single attempt; this is not an OAuth/PKCE flow.
    var callbackURL: URL {
        URL(string: "http://localhost:\(port)/\(id.uuidString.lowercased())/callback")!
    }

    var authorizationURL: URL {
        var url = URLComponents(string: "https://account.scaleway.com/authenticate")!
        url.queryItems = [URLQueryItem(name: "redirectToUrl", value: callbackURL.absoluteString)]
        return url.url!
    }

    func decodeCallback(_ url: URL) throws -> SessionEnvelope {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "http", parts.host == "localhost",
              parts.percentEncodedPath == callbackURL.path, parts.user == nil, parts.password == nil,
              parts.port == Int(port), parts.fragment == nil else { throw LoginFailure.invalidCallback }
        let tokens = (parts.queryItems ?? []).filter { $0.name == "token" }
        guard tokens.count == 1, parts.queryItems?.count == 1, let encoded = tokens.first?.value,
              let data = Data(base64Encoded: encoded),
              let envelope = try? JSONDecoder().decode(SessionEnvelope.self, from: data) else {
            throw LoginFailure.invalidToken
        }
        try envelope.validate()
        return envelope
    }
}

struct SessionEnvelope: Decodable {
    struct Metadata: Decodable {
        let jti: String
        let audienceId: String
    }
    let token: String
    let jwt: Metadata
    func validate() throws {
        guard !token.isEmpty, token.utf8.count <= 16_384,
              token.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }),
              UUID(uuidString: jwt.jti) != nil, UUID(uuidString: jwt.audienceId) != nil else {
            throw LoginFailure.invalidToken
        }
    }
    // Deliberately discard renewToken. This experiment never persists credentials.
}

struct SessionVerification: Decodable {
    let jti: String
    let audienceID: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case jti, audienceID = "audience_id", expiresAt = "expires_at"
    }

    func validate(against envelope: SessionEnvelope, now: Date = Date()) throws -> Date {
        guard jti.caseInsensitiveCompare(envelope.jwt.jti) == .orderedSame,
              audienceID.caseInsensitiveCompare(envelope.jwt.audienceId) == .orderedSame else {
            throw LoginFailure.mismatchedSession
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var expiration = formatter.date(from: expiresAt)
        if expiration == nil {
            formatter.formatOptions = [.withInternetDateTime]
            expiration = formatter.date(from: expiresAt)
        }
        guard let expiration else { throw LoginFailure.invalidResponse }
        guard expiration > now else { throw LoginFailure.expired }
        return expiration
    }
}

// Never forward a credential to a redirect target, even during an experiment.
final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum SessionVerifier {
    static func verify(_ envelope: SessionEnvelope, transport: CloudAPI.Transport? = nil) async throws -> Date {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let request = try verificationRequest(envelope)
        let data: Data
        let http: HTTPURLResponse
        if let transport { (data, http) = try await transport(request) }
        else {
            let response: URLResponse
            (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw LoginFailure.invalidResponse }
            http = response
        }
        try Task.checkCancellation()
        guard http.url == request.url, data.count <= 65_536 else { throw LoginFailure.invalidResponse }
        guard http.statusCode == 200 else { throw LoginFailure.rejected(http.statusCode) }
        guard let verification = try? JSONDecoder().decode(SessionVerification.self, from: data) else {
            throw LoginFailure.invalidResponse
        }
        return try verification.validate(against: envelope)
    }

    static func verificationRequest(_ envelope: SessionEnvelope) throws -> URLRequest {
        try envelope.validate()
        let url = URL(string: "https://api.scaleway.com/iam/v1alpha1/jwts/\(envelope.jwt.jti)")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(envelope.token, forHTTPHeaderField: "X-Session-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

