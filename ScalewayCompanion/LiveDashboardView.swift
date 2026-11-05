// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct LiveDashboardView: View {
    @ObservedObject var store: DashboardStore
    @State private var tab = 0
    @State private var account = false
    @State private var filters = false
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 40
    @Environment(\.themePalette) private var palette

    var body: some View {
        TabView(selection: $tab) {
            Tab("Overview", systemImage: "square.grid.2x2.fill", value: 0) { page("Overview", index: 0) }
            Tab("Instances", systemImage: "server.rack", value: 1) { page("Instances", index: 1) }
            Tab("Spending", systemImage: "chart.bar.xaxis", value: 2) { page("Spending", index: 2) }
        }
        .sheet(isPresented: $account) { ConnectionView(store: store) }
        .sheet(isPresented: $filters) { filterSheet }
    }

    private func page(_ title: String, index: Int) -> some View {
        NavigationStack {
            Group {
                if index == 1 {
                    content(index: index)
                        .searchable(text: $store.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Instances")
                } else { content(index: index) }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label("Cloud Companion", systemImage: "cloud").font(.subheadline).foregroundStyle(.secondary).fixedSize()
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Account", systemImage: "person.crop.circle") { account = true }.accessibilityIdentifier("accountButton")
                }
            }
        }
    }
    private func content(index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                scopePicker(showFilters: index == 1)
                if index == 0 {
                    currentSpending
                    fleetSummary
                    instanceSection(overview: true)
                } else if index == 1 { instanceSection(overview: false) }
                else { SpendingHistoryView(store: store) }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(palette.canvas).foregroundStyle(.primary)
        .refreshable { await store.refresh() }
    }
    private func scopePicker(showFilters: Bool) -> some View {
        HStack {
            Menu {
                Picker("Project", selection: $store.projectID) {
                    Text("All permitted projects").tag("")
                    ForEach(store.projects, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.projectID.isEmpty ? "All projects" : store.projectID).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }.accessibilityIdentifier("liveProjectPicker")
            Spacer(minLength: 12)
            if store.busy { ProgressView().accessibilityLabel("Refreshing cloud data") }
            if showFilters {
                Button("Filters", systemImage: "line.3.horizontal.decrease") { filters = true }
                    .frame(minHeight: 44).modifier(CompactGlassButton()).accessibilityIdentifier("instanceFilters")
            }
        }
    }
    private var currentSpending: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.spending.map { $0.period != DashboardStore.billingPeriod() } == true ? "Last loaded month" : "This month").font(.headline)
                Spacer()
                Text(store.spending?.period ?? DashboardStore.billingPeriod()).font(.subheadline).foregroundStyle(.secondary)
            }
            if let snapshot = store.spending {
                let values = BillingSummary.totals(snapshot.items, project: store.projectID)
                if values.isEmpty { Text("No consumption reported for this selection.").foregroundStyle(.secondary) }
                ForEach(values) { value in
                    Text("\(value.amount.formatted(.currency(code: value.currency))) \(value.currency)")
                        .font(.system(size: amountSize, weight: .semibold)).monospacedDigit()
                        .accessibilityIdentifier("liveSpendingTotal").fixedSize(horizontal: false, vertical: true)
                }
                Text("Estimated consumption · excl. tax").font(.footnote).foregroundStyle(.secondary)
                if values.count == 1 {
                    ConsumptionStrip(amounts: BillingSummary.categories(snapshot.items, project: store.projectID).map(\.amount)).padding(.vertical, 4)
                }
                if let error = store.spendingError {
                    InlineFailure(message: error, lastSuccess: store.spendingFetchedAt) { Task { await store.refresh() } }
                }
                Button { tab = 2 } label: {
                    HStack { Text("Spending details"); Spacer(); Image(systemName: "chevron.right").font(.footnote) }.frame(minHeight: 44)
                }
            } else if let error = store.spendingError {
                InlineFailure(message: error, lastSuccess: nil) { Task { await store.refresh() } }
                Text("Required: BillingReadOnly at organization scope.").font(.footnote).foregroundStyle(.secondary)
            } else { placeholders }
        }
    }
    private var fleetSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            let unavailable = store.zoneUpdatedAt.isEmpty
            let partial = !store.failedZones.isEmpty
            FleetSummary(running: unavailable ? "Unavailable" : "\(store.projectInstances.filter { $0.state == "running" }.count)",
                         coverage: "\(store.successfulZones.count) of \(CloudAPI.zones.count)")
            if partial { Text("Partial coverage · includes last-known states where available.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private func instanceSection(overview: Bool) -> some View {
        let items = overview ? store.projectInstances : store.visibleInstances
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(overview ? "Your Instances" : "Instances").font(overview ? .title2.bold() : .headline)
                Spacer()
                if overview { Button("See all") { tab = 1 }.frame(minHeight: 44) }
            }
            if !overview {
                Text("\(store.zone.isEmpty ? "All zones" : store.zone) · \(store.statusFilter.isEmpty ? "Any status" : store.statusFilter.capitalized)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if store.zoneUpdatedAt.isEmpty && store.busy { placeholders }
            else {
                if store.zoneUpdatedAt.isEmpty || (!overview && !store.zone.isEmpty && store.failedZones[store.zone] != nil && store.zoneUpdatedAt[store.zone] == nil) {
                    Text("Instance count unavailable").foregroundStyle(.secondary)
                } else if !overview {
                    Text("\(items.count) Instances · \(items.filter { $0.state == "running" }.count) running\(!store.failedZones.isEmpty ? " · partial coverage" : "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if items.isEmpty {
                    Text(store.failedZones.isEmpty ? "No matching Instances." : "No Instances available from the zones successfully checked.")
                        .padding(.vertical, 16).foregroundStyle(.secondary)
                    if !overview { Button("Clear filters") { resetFilters() }.frame(minHeight: 44) }
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.prefix(overview ? 2 : items.count))) { instance in
                        NavigationLink { LiveInstanceDetail(store: store, instance: instance) } label: {
                            CloudInstanceRow(name: instance.name, subtitle: "\(instance.type) · \(instance.zone)", status: instance.state.capitalized,
                                stale: store.isZoneStale(instance.zone) ? store.zoneUpdatedAt[instance.zone].map { "Last known \($0.formatted(date: .omitted, time: .shortened))" } : nil)
                        }.buttonStyle(.plain).accessibilityIdentifier("instance-\(instance.id)")
                        Divider().overlay(palette.line)
                    }
                }
            }
            if let date = store.refreshedAt {
                Button { Task { await store.refresh() } } label: {
                    Label("Checked \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
                }.disabled(store.busy)
            }
            if !store.failedZones.isEmpty {
                DisclosureGroup("\(store.failedZones.count) zones could not be checked") {
                    ForEach(store.failedZones.keys.sorted(), id: \.self) { zone in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(zone).font(.subheadline.weight(.medium))
                            Text(store.failedZones[zone] ?? "").font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                    Button("Retry failed zones") { Task { await store.refresh() } }.disabled(store.busy).frame(minHeight: 44)
                }.font(.footnote)
            }
        }
    }
    private func resetFilters() {
        store.search = ""; store.statusFilter = ""; store.projectID = ""
        Task { await store.selectZone("") }
    }
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Picker("Zone", selection: Binding(get: { store.zone }, set: { value in Task { await store.selectZone(value) } })) {
                    Text("All zones").tag("")
                    ForEach(CloudAPI.zones, id: \.self) { Text($0).tag($0) }
                }
                Picker("Status", selection: $store.statusFilter) {
                    Text("Any status").tag("")
                    ForEach(Set(store.instances.map(\.state)).sorted(), id: \.self) { Text($0.capitalized).tag($0) }
                }
                Button("Reset filters") { resetFilters() }
            }
            .scrollContentBackground(.hidden).background(palette.canvas)
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { filters = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loading cloud data").font(.subheadline).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 8).fill(palette.line).frame(width: 160, height: 40)
            RoundedRectangle(cornerRadius: 4).fill(palette.line).frame(height: 16)
        }.accessibilityLabel("Loading cloud data")
    }
}

private struct LiveInstanceDetail: View {
    @ObservedObject var store: DashboardStore
    let instance: LiveInstance
    @Environment(\.themePalette) private var palette
    var body: some View {
        let current = store.instances.first { $0.id == instance.id } ?? instance
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.footnote).foregroundStyle(.secondary)
                    Text(current.name).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("instanceDetailName")
                }
                LabeledContent("Status", value: current.state.capitalized)
                    .foregroundStyle(store.isZoneStale(current.zone) ? Theme.muted : (current.state == "running" ? Theme.success : Theme.ink))
                LabeledContent("Type", value: current.type)
                LabeledContent("Zone", value: current.zone)
                LabeledContent("Project", value: current.project)
            } header: { Text("Instance") }
            Section("Instance ID") {
                Text(current.id).font(.footnote.monospaced()).textSelection(.enabled)
                    .accessibilityLabel("Instance ID, \(current.id)")
                Button("Copy Instance ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = current.id }
            }
            if let stamp = store.zoneUpdatedAt[current.zone], store.isZoneStale(current.zone) {
                Section { Text("Last known state from \(stamp.formatted()). Refresh before relying on it.").foregroundStyle(.secondary) }
            }
            if !store.instances.contains(where: { $0.id == instance.id }) {
                Section { Text("This Instance is no longer in the loaded results. Details show its last known values.").foregroundStyle(.secondary) }
            }
            Section { Text("Read-only connection. Resource management is not enabled.").font(.footnote).foregroundStyle(.secondary) }
        }
        .scrollContentBackground(.hidden).background(palette.canvas)
        .navigationTitle(current.name).navigationBarTitleDisplayMode(.large)
    }
}

struct InlineFailure: View {
    let message: String
    let lastSuccess: Date?
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.primary)
            if let lastSuccess { Text("Last successful update \(lastSuccess.formatted(date: .abbreviated, time: .shortened)). Values shown are stale.").font(.footnote).foregroundStyle(.secondary) }
            Button("Retry", action: retry).frame(minHeight: 44)
        }.padding(.vertical, 8)
    }
}
