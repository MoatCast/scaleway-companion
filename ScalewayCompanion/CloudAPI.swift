// SPDX-License-Identifier: MPL-2.0
import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidCredentials, invalidKey, forbidden, invalidResponse, network, server(Int), keychain
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Enter a secret API key and a valid organization UUID."
        case .invalidKey: "The API key was rejected. Check whether it has expired or been revoked."
        case .forbidden: "Access denied. Check the key’s IAM permissions and organization."
        case .invalidResponse: "Scaleway returned an incomplete or unexpected response. Please refresh."
        case .network: "Could not reach Scaleway. Check your connection and retry."
        case .server(let code): "Scaleway could not complete the request (HTTP \(code)). Please retry."
        case .keychain: "The iPhone could not access secure storage. Unlock the device and retry."
        }
    }
}

struct APICredentials: Codable, Equatable, Sendable {
    let secret: String
    let organization: String
    let setupName: String?
    init(secret: String, organization: String, setupName: String? = nil) throws {
        // Reject control characters before trimming so pasted header injection cannot be accepted.
        guard !secret.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw APIError.invalidCredentials }
        let key = secret.trimmingCharacters(in: .whitespaces)
        let org = organization.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({ (33...126).contains(Int($0.value)) }), UUID(uuidString: org) != nil else { throw APIError.invalidCredentials }
        self.secret = key
        self.organization = org
        self.setupName = setupName
    }
}

struct APIMoney: Decodable, Equatable, Sendable {
    let currency: String
    let amount: Decimal
    enum CodingKeys: String, CodingKey { case currency = "currency_code", units, nanos }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = try c.decode(String.self, forKey: .currency)
        let units: Int64
        if let number = try? c.decode(Int64.self, forKey: .units) { units = number }
        else {
            let string = try c.decode(String.self, forKey: .units)
            guard let number = Int64(string) else { throw APIError.invalidResponse }
            units = number
        }
        let nanos = try c.decode(Int32.self, forKey: .nanos)
        guard currency.count == 3, currency.utf8.allSatisfy({ (65...90).contains($0) }),
              (-999_999_999...999_999_999).contains(nanos),
              !(units > 0 && nanos < 0), !(units < 0 && nanos > 0) else { throw APIError.invalidResponse }
        amount = Decimal(units) + Decimal(Int(nanos)) / Decimal(1_000_000_000)
    }
}

struct Consumption: Decodable, Sendable {
    let value: APIMoney
    let projectID: String
    let category: String
    enum CodingKeys: String, CodingKey { case value, projectID = "project_id", category = "category_name" }
}
struct SpendingSnapshot: Sendable {
    let items: [Consumption]
    let updatedAt: String?
    let period: String
}
struct LiveInstance: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let project: String
    let type: String
    let state: String
    var zone: String = ""
    enum CodingKeys: String, CodingKey { case id, name, project, state, type = "commercial_type" }
}

struct CloudAPI: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    static let zones = ["fr-par-1", "fr-par-2", "fr-par-3", "nl-ams-1", "nl-ams-2", "nl-ams-3", "pl-waw-1", "pl-waw-2", "pl-waw-3", "it-mil-1", "it-mil-2", "it-mil-3"]
    init(transport: @escaping Transport = { try await CloudAPI.send($0) }) { self.transport = transport }

    static func request(credentials: APICredentials, path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains(".."), !path.contains(":") else { throw APIError.invalidResponse }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.scaleway.com"
        components.path = path
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(credentials.secret, forHTTPHeaderField: "X-Auth-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }

    private func get<T: Decodable>(_ type: T.Type, credentials: APICredentials, path: String, query: [URLQueryItem]) async throws -> (T, HTTPURLResponse) {
        do {
            let request = try Self.request(credentials: credentials, path: path, query: query)
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard response.url?.scheme == "https", response.url?.host == "api.scaleway.com" else { throw APIError.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 401: throw APIError.invalidKey
            case 403: throw APIError.forbidden
            case 300...399: throw APIError.invalidResponse
            default: throw APIError.server(response.statusCode)
            }
            guard data.count <= 20_000_000 else { throw APIError.invalidResponse }
            do { return (try JSONDecoder().decode(type, from: data), response) }
            catch { throw APIError.invalidResponse }
        } catch is CancellationError { throw CancellationError() }
        catch let error as APIError { throw error }
        catch { throw APIError.network }
    }

    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance] {
        guard Self.zones.contains(zone) else { throw APIError.invalidResponse }
        struct Page: Decodable { let servers: [LiveInstance]; let total_count: Int? }
        var result: [LiveInstance] = []
        for page in 1...10_000 {
            let (batch, response) = try await get(Page.self, credentials: credentials,
                path: "/instance/v1/zones/\(zone)/servers", query: [
                    .init(name: "organization", value: credentials.organization),
                    .init(name: "page", value: String(page)), .init(name: "per_page", value: "100")])
            result += batch.servers
            let count: Int?
            if let bodyCount = batch.total_count { count = bodyCount }
            else if let raw = response.value(forHTTPHeaderField: "X-Total-Count") {
                guard let headerCount = Int(raw) else { throw APIError.invalidResponse }
                count = headerCount
            } else { count = nil }
            if let count {
                guard count >= 0 else { throw APIError.invalidResponse }
                if result.count >= count { return try unique(result) }
                guard !batch.servers.isEmpty else { throw APIError.invalidResponse }
            } else if batch.servers.count < 100 { return try unique(result) }
        }
        throw APIError.invalidResponse
    }
    private func unique(_ items: [LiveInstance]) throws -> [LiveInstance] {
        guard Set(items.map(\.id)).count == items.count else { throw APIError.invalidResponse }
        return items
    }

    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot {
        struct Page: Decodable {
            let consumptions: [Consumption]
            let total_count: Int
            let updated_at: String?
        }
        var result: [Consumption] = []
        var updated: String?
        for page in 1...10_000 {
            let (batch, _) = try await get(Page.self, credentials: credentials, path: "/billing/v2beta1/consumptions", query: [
                .init(name: "organization_id", value: credentials.organization), .init(name: "billing_period", value: period),
                .init(name: "page", value: String(page)), .init(name: "page_size", value: "100")])
            result += batch.consumptions
            // Show the oldest page's update time, never imply fresher data than the snapshot contains.
            if let date = batch.updated_at { updated = min(updated ?? date, date) }
            guard batch.total_count >= 0 else { throw APIError.invalidResponse }
            if result.count >= batch.total_count { return SpendingSnapshot(items: result, updatedAt: updated, period: period) }
            guard !batch.consumptions.isEmpty else { throw APIError.invalidResponse }
        }
        throw APIError.invalidResponse
    }
}
