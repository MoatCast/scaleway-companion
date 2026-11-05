// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import Charts

struct SpendingHistoryView: View {
    @ObservedObject var store: DashboardStore
    @State private var selectedCurrency = ""
    @Environment(\.themePalette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 40
    private var currency: String { store.historyCurrencies.contains(selectedCurrency) ? selectedCurrency : (store.historyCurrencies.first ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Billing month", selection: $store.selectedPeriod) {
                ForEach(store.periods.reversed(), id: \.self) { period in
                    Text(monthLabel(period)).tag(period)
                }
            }.pickerStyle(.menu).frame(minHeight: 44)
            if let snapshot = store.selectedSpending {
                let amounts = BillingSummary.totals(snapshot.items, project: store.projectID)
                Text("Estimated consumption").font(.subheadline).foregroundStyle(Theme.muted)
                if amounts.isEmpty { Text("No consumption reported for this selection.").foregroundStyle(Theme.muted) }
                ForEach(amounts) { amount in
                    Text("\(amount.amount.formatted(.currency(code: amount.currency))) \(amount.currency)")
                        .font(.system(size: amountSize, weight: .semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                if let error = store.historyErrors[store.selectedPeriod] {
                    InlineFailure(message: error, lastSuccess: nil) { Task { await store.loadHistory(force: true) } }
                    Text("Showing the last loaded values for this month.").font(.footnote).foregroundStyle(Theme.muted)
                }
                if let updated = snapshot.updatedAt {
                    Text("Billing updated: \(timestamp(updated))").font(.caption).foregroundStyle(Theme.muted)
                }
            } else if let error = store.historyErrors[store.selectedPeriod] {
                InlineFailure(message: error, lastSuccess: nil) { Task { await store.loadHistory(force: true) } }
            } else { ProgressView("Loading billing month…") }
            VStack(alignment: .leading, spacing: 12) { historyChart }
                .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
            if let snapshot = store.selectedSpending {
                Text("Where it goes").font(.title2.bold())
                ForEach(BillingSummary.categories(snapshot.items, project: store.projectID)) { category in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(category.category.replacingOccurrences(of: "_", with: " ").capitalized)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(category.amount.formatted(.currency(code: category.currency))) \(category.currency)")
                            .monospacedDigit().multilineTextAlignment(.trailing)
                    }.font(.body).padding(.vertical, 10)
                    Divider()
                }
            }
            Text("Estimated consumption, excluding tax. Charges can be delayed. Discounts and credits are not deducted here; this is not a final invoice.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        .task { await store.loadHistory() }
    }
    @ViewBuilder private var historyChart: some View {
        HStack {
            Text("Monthly history").font(.headline)
            Spacer()
            if store.historyBusy { ProgressView().accessibilityLabel("Loading spending history") }
        }
        if store.historyCurrencies.count > 1 {
            Picker("History currency", selection: Binding(get: { currency }, set: { selectedCurrency = $0 })) {
                ForEach(store.historyCurrencies, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
        }
        if !currency.isEmpty {
            let points = store.historyPoints(currency: currency)
            Chart(points) { point in
                if let amount = point.amount {
                    BarMark(x: .value("Month", point.period), y: .value(currency, NSDecimalNumber(decimal: amount).doubleValue))
                        .foregroundStyle(point.period == store.periods.last ? palette.accent : palette.accent.opacity(0.25))
                        .accessibilityLabel(monthLabel(point.period))
                        .accessibilityValue("\(amount.formatted(.currency(code: currency))) \(currency)")
                }
            }
            .chartXScale(domain: store.periods)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let period = value.as(String.self) { Text(monthLabel(period, short: true)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number, format: .currency(code: currency).precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .frame(height: 200)
            Text("\(currency) · \(monthLabel(store.periods.last ?? "")) is month-to-date. Missing months have no bar.")
                .font(.caption).foregroundStyle(Theme.muted)
            DisclosureGroup("Monthly amounts") {
                ForEach(points) { point in
                    HStack {
                        Text(monthLabel(point.period))
                        Spacer()
                        if let amount = point.amount {
                            Text(amount.formatted(.currency(code: currency))).monospacedDigit()
                        } else {
                            Text("Unavailable").foregroundStyle(Theme.muted)
                        }
                    }.font(.subheadline).padding(.vertical, 8)
                }
            }.font(.subheadline)
        } else if !store.historyBusy {
            Text("No currency information is available for this selection.").foregroundStyle(Theme.muted)
        }
        if !store.historyErrors.isEmpty {
            Text("Some months could not be refreshed. Unavailable months are not treated as zero.").font(.footnote).foregroundStyle(Theme.muted)
            Button("Retry history") { Task { await store.loadHistory(force: true) } }
                .disabled(store.historyBusy || store.busy).frame(minHeight: 44)
        }
    }
    private func monthLabel(_ period: String, short: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: period) else { return period }
        formatter.locale = .current
        formatter.dateFormat = short ? "MMM" : "MMM yyyy"
        return formatter.string(from: date)
    }
    private func timestamp(_ string: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: string)
        if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: string) }
        return date?.formatted(date: .abbreviated, time: .shortened) ?? string
    }
}
