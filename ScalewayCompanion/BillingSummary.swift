// SPDX-License-Identifier: MPL-2.0
import Foundation

struct CurrencyAmount: Identifiable, Equatable {
    let currency: String
    let amount: Decimal
    var id: String { currency }
}
struct CategoryAmount: Identifiable {
    let category: String
    let currency: String
    let amount: Decimal
    var id: String { currency + ":" + category }
}
struct MonthlyAmount: Identifiable {
    let period: String
    let amount: Decimal?
    var id: String { period }
}
enum BillingSummary {
    /// "2026-11" → "Nov 2026" (or "Nov" when short), ordered for the user's locale.
    static func monthLabel(_ period: String, short: Bool = false, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: period) else { return period }
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(short ? "MMM" : "MMMyyyy")
        return formatter.string(from: date)
    }
    static func categories(_ items: [Consumption], project: String = "") -> [CategoryAmount] {
        let filtered = items.filter { project.isEmpty || $0.projectID == project }
        let currencies = Dictionary(grouping: filtered, by: { $0.value.currency })
        return currencies.keys.sorted().flatMap { currency in
            let categories = Dictionary(grouping: currencies[currency] ?? [], by: { $0.category })
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .currency
            formatter.currencyCode = currency
            let precision = formatter.maximumFractionDigits
            return categories.keys.sorted().map { category in
                let exact = (categories[category] ?? []).reduce(Decimal.zero) { $0 + $1.value.amount }
                var input = exact, rounded = Decimal.zero
                NSDecimalRound(&rounded, &input, precision, .plain)
                return CategoryAmount(category: category.isEmpty ? "Other" : category, currency: currency, amount: rounded)
            }
        }
    }
    static func totals(_ items: [Consumption], project: String = "") -> [CurrencyAmount] {
        let groups = Dictionary(grouping: categories(items, project: project), by: \.currency)
        return groups.keys.sorted().map { currency in
            CurrencyAmount(currency: currency, amount: (groups[currency] ?? []).reduce(.zero) { $0 + $1.amount })
        }
    }
}
