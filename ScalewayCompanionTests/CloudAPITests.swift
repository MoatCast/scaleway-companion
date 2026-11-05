// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

final class CloudAPITests: XCTestCase {
    private let organization = "11111111-1111-4111-8111-111111111111"

    func testCredentialsRejectHeaderInjectionAndInvalidOrganization() throws {
        XCTAssertThrowsError(try APICredentials(secret: "key\r\nX-Test: yes", organization: organization))
        XCTAssertThrowsError(try APICredentials(secret: "key", organization: "../anything"))
        XCTAssertThrowsError(try APICredentials(secret: "", organization: organization))
        let credentials = try APICredentials(secret: " key ", organization: organization)
        let request = try CloudAPI.request(credentials: credentials, path: "/instance/v1/zones/fr-par-1/servers", query: [])
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth-Token"), "key")
        XCTAssertEqual(request.url?.host, "api.scaleway.com")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertThrowsError(try CloudAPI.request(credentials: credentials, path: "https://other.example", query: []))
    }

    func testMoneyDecodesStringUnitsWithoutFloatingPointRounding() throws {
        let string = #"{"currency_code":"EUR","units":"9007199254740993","nanos":123456789}"#
        let money = try JSONDecoder().decode(APIMoney.self, from: Data(string.utf8))
        XCTAssertEqual(money.amount, Decimal(string: "9007199254740993.123456789"))
        let zero = #"{"currency_code":"EUR","units":0,"nanos":0}"#
        XCTAssertEqual(try JSONDecoder().decode(APIMoney.self, from: Data(zero.utf8)).amount, .zero)
        let numeric = #"{"currency_code":"USD","units":-1,"nanos":-250000000}"#
        XCTAssertEqual(try JSONDecoder().decode(APIMoney.self, from: Data(numeric.utf8)).amount, Decimal(string: "-1.25"))
        for json in [#"{"currency_code":"EUR","units":"oops","nanos":0}"#,
                     #"{"currency_code":"EUR","units":1,"nanos":-1}"#,
                     #"{"currency_code":"EUR","units":0,"nanos":1000000000}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(APIMoney.self, from: Data(json.utf8)))
        }
    }

    func testPaginationAndBillingPeriodAndOrganizationFilters() async throws {
        let transport = FixtureTransport(responses: [
            (#"{"consumptions":[{"value":{"currency_code":"EUR","units":"1","nanos":1},"project_id":"p1","category_name":"Compute"}],"total_count":2,"updated_at":"2026-11-04T10:00:00Z"}"#, [:], 200),
            (#"{"consumptions":[{"value":{"currency_code":"USD","units":2,"nanos":0},"project_id":"p2","category_name":"Storage"}],"total_count":2,"updated_at":"2026-11-04T10:00:00Z"}"#, [:], 200)
        ])
        let client = CloudAPI(transport: { try await transport.send($0) })
        let result = try await client.spending(credentials: APICredentials(secret: "fixture", organization: organization), period: "2026-11")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(Set(result.items.map(\.value.currency)), ["EUR", "USD"])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "page", value: "2")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "billing_period", value: "2026-11")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "organization_id", value: organization)))
    }

    func testInstancePaginationUsesTotalCountHeaderAndKeepsRealState() async throws {
        let transport = FixtureTransport(responses: [
            (#"{"servers":[{"id":"one","name":"example","project":"p1","commercial_type":"DEV1-S","state":"starting"}]}"#, ["X-Total-Count":"2"], 200),
            (#"{"servers":[{"id":"two","name":"example2","project":"p2","commercial_type":"DEV1-M","state":"running"}]}"#, ["X-Total-Count":"2"], 200)
        ])
        let result = try await CloudAPI(transport: { try await transport.send($0) }).instances(credentials: APICredentials(secret: "fixture", organization: organization), zone: "fr-par-1")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].state, "starting")
        let count = await transport.requestCount()
        XCTAssertEqual(count, 2)
    }

    func testInstancePaginationUsesDocumentedBodyCount() async throws {
        let transport = FixtureTransport(responses: [
            (#"{"servers":[{"id":"one","name":"example","project":"p1","commercial_type":"DEV1-S","state":"running"}],"total_count":2}"#, [:], 200),
            (#"{"servers":[{"id":"two","name":"example2","project":"p1","commercial_type":"DEV1-S","state":"stopped"}],"total_count":2}"#, [:], 200)
        ])
        let result = try await CloudAPI(transport: { try await transport.send($0) }).instances(credentials: APICredentials(secret: "fixture", organization: organization), zone: "fr-par-1")
        XCTAssertEqual(result.count, 2)
    }

    func testPermissionAndInvalidKeyErrorsAreSanitized() async throws {
        for (status, expected) in [(401, APIError.invalidKey), (403, APIError.forbidden)] {
            let transport = FixtureTransport(responses: [("sensitive server response", [:], status)])
            do {
                _ = try await CloudAPI(transport: { try await transport.send($0) }).instances(credentials: APICredentials(secret: "fixture", organization: organization), zone: "fr-par-1")
                XCTFail("Expected rejection")
            } catch { XCTAssertEqual(error as? APIError, expected) }
        }
    }

    func testPrematureEmptyPageIsNotReportedAsComplete() async throws {
        let transport = FixtureTransport(responses: [(#"{"consumptions":[],"total_count":2}"#, [:], 200)])
        do {
            _ = try await CloudAPI(transport: { try await transport.send($0) }).spending(credentials: APICredentials(secret: "fixture", organization: organization), period: "2026-11")
            XCTFail("Expected incomplete response failure")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }
}

actor FixtureTransport {
    var requests: [URLRequest] = []
    var responses: [(String, [String:String], Int)]
    init(responses: [(String, [String:String], Int)]) { self.responses = responses }
    func requestCount() -> Int { requests.count }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw APIError.invalidResponse }
        let (json, headers, code) = responses.removeFirst()
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!)
    }
}
