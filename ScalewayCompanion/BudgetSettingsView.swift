// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// Account section (Paper 13): monthly budget with best-effort 80 % / 100 % alerts.
struct BudgetSettingsSection: View {
    @ObservedObject var store: DashboardStore
    @State private var enabled = false
    @State private var amount: Decimal = 100
    @State private var currency = "EUR"
    @State private var denied = false
    @State private var loaded = false
    @Environment(\.themePalette) private var palette
    private var totals: [CurrencyAmount] { store.spending.map { BillingSummary.totals($0.items) } ?? [] }
    private var used: Decimal? { totals.first { $0.currency == currency }?.amount }

    var body: some View {
        Section {
            Toggle(isOn: $enabled) { Label("Notify me", systemImage: "bell") }
                .tint(Theme.success).accessibilityIdentifier("budgetToggle")
            if enabled {
                LabeledContent("Monthly budget") {
                    TextField("Amount", value: $amount, format: .currency(code: currency))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).foregroundStyle(palette.accent)
                        .accessibilityIdentifier("budgetAmount")
                }
                let choices = BudgetCheck.currencyChoices(selected: currency, totals: totals)
                if choices.count > 1 {
                    Picker("Currency", selection: $currency) { ForEach(choices, id: \.self) { Text($0).tag($0) } }
                        .accessibilityIdentifier("budgetCurrency")
                }
                if let used, amount > 0 {
                    let fraction = min(1, NSDecimalNumber(decimal: used / amount).doubleValue)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(used.formatted(.currency(code: currency))) used this month")
                            Spacer()
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        }.font(.subheadline).foregroundStyle(.secondary)
                        ProgressView(value: fraction).tint(palette.accent)
                    }.padding(.vertical, 6)
                }
            }
            if denied {
                Label("Notifications are off for Cloud Companion. Turn them on in Settings to get budget alerts.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Budget alert").font(.headline).foregroundStyle(.primary).textCase(nil)
        } footer: {
            Text("You’ll get a notification at 80% and 100% of your budget. iOS decides when the app checks in the background, usually a few times a day, and billing data can lag — so this is best effort, not a guarantee.")
        }
        .onAppear(perform: load)
        .onChange(of: enabled) { _, on in
            guard loaded else { return }
            if on { Task { denied = !(await BudgetMonitor.requestPermission()); if denied { enabled = false } else { save() } } }
            else { save() }
        }
        .onChange(of: amount) { _, _ in if loaded { save() } }
        .onChange(of: currency) { _, _ in if loaded { save() } }
        .onChange(of: totals.map(\.currency)) { _, billed in
            // Spending arrived after the view appeared: replace the EUR placeholder if nothing was saved yet.
            if store.budget.settings == nil, let first = billed.first, !billed.contains(currency) { currency = first }
        }
    }
    private func load() {
        let saved = store.budget.settings
        enabled = saved?.enabled ?? false
        amount = saved?.amount ?? 100
        currency = saved?.currency ?? totals.first?.currency ?? "EUR"
        DispatchQueue.main.async { loaded = true }
    }
    private func save() {
        guard let organization = store.organization else { return }
        store.budget.update(BudgetSettings(enabled: enabled, amount: amount, currency: currency, organization: organization))
        BudgetMonitor.schedule()
    }
}
