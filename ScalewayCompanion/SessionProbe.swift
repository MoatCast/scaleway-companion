// SPDX-License-Identifier: MPL-2.0
import Foundation

struct SessionProbe: Sendable {
    enum Capability { case instances, spending }
    enum Outcome: Equatable {
        case verified, rejected(Int), invalidResponse, network
        var description: String {
            switch self {
            case .verified: "API access verified"
            case .rejected(let code): "Access rejected (HTTP \(code))"
            case .invalidResponse: "Unexpected API response"
            case .network: "Network request failed"
            }
        }
    }
    private let transport: CloudAPI.Transport
    init(transport: @escaping CloudAPI.Transport = { try await CloudAPI.send($0) }) { self.transport = transport }

    func read(_ capability: Capability, envelope: SessionEnvelope, organization: String, now: Date = Date()) async throws -> Outcome {
        try Task.checkCancellation()
        try envelope.validate()
        guard UUID(uuidString: organization) != nil else { throw LoginFailure.invalidResponse }
        var url = URLComponents(string: "https://api.scaleway.com")!
        switch capability {
        case .instances:
            // One page in one zone proves this capability; it is not a resource inventory.
            url.path = "/instance/v1/zones/fr-par-1/servers"
            url.queryItems = [.init(name: "organization", value: organization), .init(name: "page", value: "1"), .init(name: "per_page", value: "1")]
        case .spending:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM"
            url.path = "/billing/v2beta1/consumptions"
            url.queryItems = [.init(name: "organization_id", value: organization), .init(name: "billing_period", value: formatter.string(from: now)), .init(name: "page", value: "1"), .init(name: "page_size", value: "1")]
        }
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(envelope.token, forHTTPHeaderField: "X-Session-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard response.url == request.url, data.count <= 1_000_000 else { return .invalidResponse }
            guard response.statusCode == 200 else { return .rejected(response.statusCode) }
            struct Instances: Decodable { let servers: [LiveInstance] }
            struct Spending: Decodable { let consumptions: [Consumption] }
            switch capability {
            case .instances: _ = try JSONDecoder().decode(Instances.self, from: data)
            case .spending: _ = try JSONDecoder().decode(Spending.self, from: data)
            }
            return .verified
        } catch is CancellationError { throw CancellationError() }
        catch is DecodingError { return .invalidResponse }
        catch { try Task.checkCancellation(); return .network }
    }
}
