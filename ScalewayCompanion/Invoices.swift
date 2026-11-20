// SPDX-License-Identifier: MPL-2.0
import Foundation

struct Invoice: Decodable, Identifiable, Sendable {
    let id: String
    let number: Int?
    let state: String
    let billingPeriod: Date?
    let issuedDate: Date?
    let dueDate: Date?
    let totalUntaxed: APIMoney?
    let totalTaxed: APIMoney?
    let totalTax: APIMoney?
    let totalDiscount: APIMoney?
    let totalUndiscount: APIMoney?
    /// UTC "yyyy-MM" of the billed month, for `BillingSummary.monthLabel`.
    var billingMonth: String? { billingPeriod.map { DashboardStore.billingPeriod(now: $0) } }

    enum CodingKeys: String, CodingKey {
        case id, number, state
        case billingPeriod = "billing_period", issuedDate = "issued_date", dueDate = "due_date"
        case totalUntaxed = "total_untaxed", totalTaxed = "total_taxed", totalTax = "total_tax"
        case totalDiscount = "total_discount", totalUndiscount = "total_undiscount"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decodeIfPresent(Int.self, forKey: .number)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        func date(_ key: CodingKeys) throws -> Date? {
            try c.decodeIfPresent(String.self, forKey: key).flatMap(Self.parseDate)
        }
        billingPeriod = try date(.billingPeriod)
        issuedDate = try date(.issuedDate)
        dueDate = try date(.dueDate)
        totalUntaxed = try c.decodeIfPresent(APIMoney.self, forKey: .totalUntaxed)
        totalTaxed = try c.decodeIfPresent(APIMoney.self, forKey: .totalTaxed)
        totalTax = try c.decodeIfPresent(APIMoney.self, forKey: .totalTax)
        totalDiscount = try c.decodeIfPresent(APIMoney.self, forKey: .totalDiscount)
        totalUndiscount = try c.decodeIfPresent(APIMoney.self, forKey: .totalUndiscount)
    }
    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

extension CloudAPI {
    func invoices(credentials: APICredentials) async throws -> [Invoice] {
        struct Page: Decodable { let invoices: [Invoice]; let total_count: Int }
        var result: [Invoice] = []
        for page in 1...1_000 {
            let (batch, _) = try await get(Page.self, credentials: credentials, path: "/billing/v2beta1/invoices", query: [
                .init(name: "organization_id", value: credentials.organization), .init(name: "order_by", value: "issued_date_desc"),
                .init(name: "page", value: String(page)), .init(name: "page_size", value: "100")])
            result += batch.invoices
            guard batch.total_count >= 0 else { throw APIError.invalidResponse }
            if result.count >= batch.total_count { return result }
            guard !batch.invoices.isEmpty else { throw APIError.invalidResponse }
        }
        throw APIError.invalidResponse
    }
}
