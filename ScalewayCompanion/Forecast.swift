// SPDX-License-Identifier: MPL-2.0
import Foundation

enum Forecast {
    /// Linear month-end projection of `total` for the current UTC billing month.
    /// Returns nil for other months and during the first three days, when the projection is unreliable.
    static func monthEnd(total: Decimal, currency: String, period: String, now: Date) -> Decimal? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard period == DashboardStore.billingPeriod(now: now),
              let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        let elapsedDays = Decimal(now.timeIntervalSince(month.start)) / 86_400
        guard elapsedDays >= 3 else { return nil }
        let days = Decimal(calendar.range(of: .day, in: .month, for: now)!.count)
        var projected = total / elapsedDays * days, rounded = Decimal.zero
        NSDecimalRound(&rounded, &projected, BillingSummary.precision(currency), .plain)
        return rounded
    }
}
