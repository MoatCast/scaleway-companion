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
struct ResourceAmount: Identifiable {
    let name: String
    let product: String
    let currency: String
    let amount: Decimal
    var id: String { currency + ":" + name }
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
    static func resources(_ items: [Consumption], project: String = "") -> [ResourceAmount] {
        let filtered = items.filter { project.isEmpty || $0.projectID == project }
        let groups = Dictionary(grouping: filtered) { [$0.resourceName.isEmpty ? "Other" : $0.resourceName, $0.value.currency] }
        return groups.map { key, lines in
            let exact = lines.reduce(Decimal.zero) { $0 + $1.value.amount }
            var input = exact, rounded = Decimal.zero
            NSDecimalRound(&rounded, &input, precision(key[1]), .plain)
            return ResourceAmount(name: key[0], product: lines.first { !$0.productName.isEmpty }?.productName ?? "", currency: key[1], amount: rounded)
        }
        .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : ($0.name, $0.currency) < ($1.name, $1.currency) }
    }
    /// Fraction digits the currency displays (EUR 2, JPY 0, BHD 3).
    static func precision(_ currency: String) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.maximumFractionDigits
    }
    static func totals(_ items: [Consumption], project: String = "") -> [CurrencyAmount] {
        let groups = Dictionary(grouping: categories(items, project: project), by: \.currency)
        return groups.keys.sorted().map { currency in
            CurrencyAmount(currency: currency, amount: (groups[currency] ?? []).reduce(.zero) { $0 + $1.amount })
        }
    }
}
