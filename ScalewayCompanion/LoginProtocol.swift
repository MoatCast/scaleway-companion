// SPDX-License-Identifier: MPL-2.0

import Foundation

enum LoginFailure: Error, LocalizedError, Equatable {
    case invalidCallback, invalidToken, invalidResponse, rejected(Int), mismatchedSession, expired

    var errorDescription: String? {
        switch self {
        case .invalidCallback: "The callback did not match this sign-in attempt. No session was accepted."
        case .invalidToken: "Scaleway returned an unexpected token format. No session was accepted."
        case .invalidResponse: "Scaleway returned an unexpected verification response."
        case .rejected(let status): "The callback arrived, but Scaleway could not verify API access (HTTP \(status)). This can also indicate missing IAM permissions."
        case .mismatchedSession: "The returned session did not match Scaleway’s verification response."
        case .expired: "The session has expired. Start a new sign-in attempt."
        }
    }
}

struct LoginAttempt {
    static let scheme = "scalewaycompanion"
    let id: UUID

    init(id: UUID = UUID()) { self.id = id }

    // A per-attempt path correlates the callback. This is an experimental CLI-style
    // token handoff, not OAuth/PKCE; provider support for this scheme is unconfirmed.
    var callbackURL: URL {
        URL(string: "\(Self.scheme)://login/callback/\(id.uuidString.lowercased())")!
    }

    var authorizationURL: URL {
        var url = URLComponents(string: "https://account.scaleway.com/authenticate")!
        url.queryItems = [URLQueryItem(name: "redirectToUrl", value: callbackURL.absoluteString)]
        return url.url!
    }

    func decodeCallback(_ url: URL) throws -> SessionEnvelope {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == Self.scheme, parts.host == "login",
              parts.path == callbackURL.path, parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil else { throw LoginFailure.invalidCallback }
        let tokens = (parts.queryItems ?? []).filter { $0.name == "token" }
        guard tokens.count == 1, let encoded = tokens.first?.value,
              let data = Data(base64Encoded: encoded),
              let envelope = try? JSONDecoder().decode(SessionEnvelope.self, from: data) else {
            throw LoginFailure.invalidToken
        }
        // Do not allow callback-controlled headers or URL path components.
        guard !envelope.token.isEmpty, envelope.token.utf8.count <= 16_384,
              envelope.token.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0) }),
              UUID(uuidString: envelope.jwt.jti) != nil,
              UUID(uuidString: envelope.jwt.audienceId) != nil else { throw LoginFailure.invalidToken }
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
    static func verify(_ envelope: SessionEnvelope) async throws -> Date {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let request = try verificationRequest(envelope)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LoginFailure.invalidResponse }
        guard http.statusCode == 200 else { throw LoginFailure.rejected(http.statusCode) }
        guard let verification = try? JSONDecoder().decode(SessionVerification.self, from: data) else {
            throw LoginFailure.invalidResponse
        }
        return try verification.validate(against: envelope)
    }

    static func verificationRequest(_ envelope: SessionEnvelope) throws -> URLRequest {
        guard UUID(uuidString: envelope.jwt.jti) != nil,
              !envelope.token.isEmpty,
              !envelope.token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw LoginFailure.invalidToken
        }
        let url = URL(string: "https://api.scaleway.com/iam/v1alpha1/jwts/\(envelope.jwt.jti)")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(envelope.token, forHTTPHeaderField: "X-Session-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

