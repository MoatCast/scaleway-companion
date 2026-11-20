// SPDX-License-Identifier: MPL-2.0
import Foundation

struct BudgetSettings: Codable, Equatable {
    var enabled: Bool
    var amount: Decimal
    var currency: String
    var organization: String
}

/// Highest threshold already notified in `period`, so each level alerts once per month.
struct BudgetState: Codable, Equatable {
    var period: String
    var notifiedPercent: Int
}

enum BudgetCheck {
    static let thresholds = [80, 100]

    static func evaluate(settings: BudgetSettings, totals: [CurrencyAmount], period: String, organization: String,
                         state: BudgetState?) -> (alertPercent: Int?, state: BudgetState) {
        let current = state?.period == period ? state! : BudgetState(period: period, notifiedPercent: 0)
        guard settings.enabled, settings.amount > 0, settings.organization == organization,
              let total = totals.first(where: { $0.currency == settings.currency })?.amount else { return (nil, current) }
        let crossed = thresholds.last { total * 100 >= settings.amount * Decimal($0) } ?? 0
        guard crossed > current.notifiedPercent else { return (nil, current) }
        return (crossed, BudgetState(period: period, notifiedPercent: crossed))
    }
}

struct BudgetStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var settings: BudgetSettings? {
        get { read("budget.settings") }
        nonmutating set { write(newValue, "budget.settings") }
    }
    var state: BudgetState? {
        get { read("budget.state") }
        nonmutating set { write(newValue, "budget.state") }
    }
    func clear() { defaults.removeObject(forKey: "budget.settings"); defaults.removeObject(forKey: "budget.state") }
    private func read<T: Decodable>(_ key: String) -> T? { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    private func write<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
