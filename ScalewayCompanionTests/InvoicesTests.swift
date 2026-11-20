// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

final class InvoicesTests: XCTestCase {
    private let organization = "11111111-1111-4111-8111-111111111111"
    private func money(_ units: Int, _ nanos: Int = 0) -> String { #"{"currency_code":"EUR","units":\#(units),"nanos":\#(nanos)}"# }
    private func invoice(_ id: String, number: Int, state: String) -> String {
        #"{"id":"\#(id)","organization_id":"\#(organization)","billing_period":"2026-10-01T00:00:00Z","issued_date":"2026-11-01T08:12:45.123Z","due_date":"2026-11-15T00:00:00Z","total_untaxed":\#(money(44, 270000000)),"total_taxed":\#(money(51, 620000000)),"total_tax":\#(money(8, 600000000)),"total_discount":\#(money(1, 250000000)),"total_undiscount":\#(money(44, 270000000)),"type":"periodic","state":"\#(state)","number":\#(number),"seller_name":"Scaleway SAS"}"#
    }

    func testInvoicesDecodeFollowPaginationAndSendFilters() async throws {
        let transport = FixtureTransport(responses: [
            (#"{"invoices":[\#(invoice("22222222-2222-4222-8222-222222222222", number: 4021856, state: "issued")),\#(invoice("33333333-3333-4333-8333-333333333333", number: 3987412, state: "paid"))],"total_count":3}"#, [:], 200),
            (#"{"invoices":[\#(invoice("44444444-4444-4444-8444-444444444444", number: 3951077, state: "paid"))],"total_count":3}"#, [:], 200)
        ])
        let result = try await CloudAPI(transport: { try await transport.send($0) })
            .invoices(credentials: APICredentials(secret: "fixture", organization: organization))
        XCTAssertEqual(result.map(\.number), [4021856, 3987412, 3951077])
        XCTAssertEqual(result[0].state, "issued")
        XCTAssertEqual(result[0].totalTaxed?.amount, Decimal(string: "51.62"))
        XCTAssertEqual(result[0].totalDiscount?.amount, Decimal(string: "1.25"))
        XCTAssertNotNil(result[0].issuedDate)   // fractional seconds
        XCTAssertNotNil(result[0].dueDate)      // whole seconds
        XCTAssertEqual(result[0].billingMonth, "2026-10")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/billing/v2beta1/invoices")
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "organization_id", value: organization)))
        XCTAssertTrue(query.contains(URLQueryItem(name: "order_by", value: "issued_date_desc")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "page", value: "2")))
    }

    func testEmptyInvoiceListIsEmptyNotError() async throws {
        let transport = FixtureTransport(responses: [(#"{"invoices":[],"total_count":0}"#, [:], 200)])
        let result = try await CloudAPI(transport: { try await transport.send($0) })
            .invoices(credentials: APICredentials(secret: "fixture", organization: organization))
        XCTAssertTrue(result.isEmpty)
    }

    func testInvoiceResponseFromAnotherHostIsRejected() async throws {
        let api = CloudAPI(transport: { request in
            (Data(#"{"invoices":[],"total_count":0}"#.utf8), HTTPURLResponse(url: URL(string: "https://evil.example/billing")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await api.invoices(credentials: APICredentials(secret: "fixture", organization: organization))
            XCTFail("expected rejection")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }

    private let invoiceID = "22222222-2222-4222-8222-222222222222"
    private func pdfJSON(name: String, type: String = "application/pdf", bytes: String = "%PDF-1.7 fixture") -> String {
        #"{"name":"\#(name)","content_type":"\#(type)","content":"\#(Data(bytes.utf8).base64EncodedString())"}"#
    }

    func testInvoicePDFWritesDecodedFileToTemporaryDirectory() async throws {
        let transport = FixtureTransport(responses: [(pdfJSON(name: "invoice-4021856.pdf"), [:], 200)])
        let url = try await CloudAPI(transport: { try await transport.send($0) })
            .invoicePDF(credentials: APICredentials(secret: "fixture", organization: organization), id: invoiceID)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(try Data(contentsOf: url).starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(url.lastPathComponent, "invoice-4021856.pdf")
        let request = await transport.requests.first
        XCTAssertEqual(request?.url?.path, "/billing/v2beta1/invoices/\(invoiceID)/download")
        XCTAssertTrue(URLComponents(url: request!.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains(URLQueryItem(name: "file_type", value: "pdf")))
    }

    func testInvoicePDFRejectsNonUUIDBeforeAnyRequest() async throws {
        let transport = FixtureTransport(responses: [])
        do {
            _ = try await CloudAPI(transport: { try await transport.send($0) })
                .invoicePDF(credentials: APICredentials(secret: "fixture", organization: organization), id: "../../etc")
            XCTFail("expected rejection")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        let count = await transport.requestCount()
        XCTAssertEqual(count, 0)
    }

    func testInvoicePDFRejectsWrongContentType() async throws {
        let transport = FixtureTransport(responses: [(pdfJSON(name: "x.html", type: "text/html", bytes: "<html>"), [:], 200)])
        do {
            _ = try await CloudAPI(transport: { try await transport.send($0) })
                .invoicePDF(credentials: APICredentials(secret: "fixture", organization: organization), id: invoiceID)
            XCTFail("expected rejection")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }

    func testInvoicePDFSanitizesTraversalInFileName() async throws {
        let transport = FixtureTransport(responses: [(pdfJSON(name: "../../x"), [:], 200)])
        let url = try await CloudAPI(transport: { try await transport.send($0) })
            .invoicePDF(credentials: APICredentials(secret: "fixture", organization: organization), id: invoiceID)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "x.pdf")
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path))
    }

    func testInvoicePDFAcceptsRawPDFBody() async throws {
        let transport = FixtureTransport(responses: [("%PDF-1.7 raw", ["Content-Type": "application/pdf"], 200)])
        let url = try await CloudAPI(transport: { try await transport.send($0) })
            .invoicePDF(credentials: APICredentials(secret: "fixture", organization: organization), id: invoiceID)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(try Data(contentsOf: url).starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(url.pathExtension, "pdf")
    }

    @MainActor
    func testDisconnectClearsLoadedInvoices() async throws {
        let store = DashboardStore(api: InvoiceService(), vault: MemoryVault())
        await store.connect(secret: "fixture", organization: organization)
        await store.loadInvoices()
        XCTAssertEqual(store.invoices?.count, 1)
        await store.disconnect()
        XCTAssertNil(store.invoices)
    }
}

struct InvoiceService: CloudService {
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance] { [] }
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot { SpendingSnapshot(items: [], updatedAt: nil, period: period) }
    func invoices(credentials: APICredentials) async throws -> [Invoice] {
        let json = #"{"id":"22222222-2222-4222-8222-222222222222","state":"paid","number":1}"#
        return [try JSONDecoder().decode(Invoice.self, from: Data(json.utf8))]
    }
}
