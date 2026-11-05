// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import Charts

struct DemoDashboardView: View {
    var onConnect: () -> Void = {}
    @State private var tab = 0
    @State private var project = Project.all
    @State private var instances = DemoData.instances
    @State private var search = ""
    @State private var status = ""
    @State private var zone = ""
    @State private var filters = false
    @State private var account = false
    @Environment(\.themePalette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 40
    private var projectInstances: [CloudInstance] { instances.filter { project == .all || $0.project == project } }
    private var filtered: [CloudInstance] {
        projectInstances.filter {
            (status.isEmpty || ($0.running ? "running" : "stopped") == status) && (zone.isEmpty || $0.zone == zone) &&
            (search.isEmpty || [$0.name, $0.type, $0.zone].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        TabView(selection: $tab) {
            Tab("Overview", systemImage: "square.grid.2x2.fill", value: 0) { page("Overview", index: 0) }
            Tab("Instances", systemImage: "server.rack", value: 1) { page("Instances", index: 1) }
            Tab("Spending", systemImage: "chart.bar.xaxis", value: 2) { page("Spending", index: 2) }
        }
        .sheet(isPresented: $account) { demoAccount }
        .sheet(isPresented: $filters) { demoFilters }
    }
    private func page(_ title: String, index: Int) -> some View {
        NavigationStack {
            Group {
                if index == 1 { content(index).searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Instances") }
                else { content(index) }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Text("Cloud Companion · Demo").font(.subheadline).foregroundStyle(.secondary).fixedSize() }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Account", systemImage: "person.crop.circle") { account = true }.accessibilityIdentifier("accountButton")
                }
            }
        }
    }
    private func content(_ index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Menu {
                        Picker("Project", selection: $project) { ForEach(Project.allCases) { Text($0.rawValue).tag($0) } }
                    } label: {
                        HStack(spacing: 4) { Text(project.rawValue); Image(systemName: "chevron.down").font(.caption.weight(.semibold)) }
                            .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }.accessibilityIdentifier("projectPicker")
                    Spacer()
                    if index == 1 {
                        Button("Filters", systemImage: "line.3.horizontal.decrease") { filters = true }.frame(minHeight: 44).modifier(CompactGlassButton())
                    }
                }
                if index != 1 { spending(showLink: index == 0) }
                if index == 0 {
                    FleetSummary(running: "\(projectInstances.filter(\.running).count)", coverage: "12")
                    instanceSection(overview: true)
                } else if index == 1 { instanceSection(overview: false) }
                else {
                    if project == .all { history }
                    categories
                    projectSpending
                    Text("Consumption is an estimate, not a final invoice. Charges can take time to appear.").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Sample data · no cloud resources connected").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("demoNotice")
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }.background(palette.canvas)
    }
    private func spending(showLink: Bool) -> some View {
        let value = Spending.sample(for: project)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text("This month").font(.headline); Spacer(); Text("Nov 2026").font(.subheadline).foregroundStyle(.secondary) }
            Text(Spending.euros(value.total)).font(.system(size: amountSize, weight: .semibold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("spendingTotal")
            Text("Estimated consumption · excl. tax · sample period").font(.footnote).foregroundStyle(.secondary)
            ConsumptionStrip(amounts: [Decimal(value.compute), Decimal(value.storage), Decimal(value.network)]).padding(.vertical, 4)
            if showLink {
                Button { tab = 2 } label: {
                    HStack { Text("Spending details"); Spacer(); Image(systemName: "chevron.right").font(.footnote) }.frame(minHeight: 44)
                }
            }
        }
    }
    private func instanceSection(overview: Bool) -> some View {
        let values = overview ? Array(projectInstances.prefix(2)) : filtered
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(overview ? "Your Instances" : "\(values.count) Instances").font(.title2.bold())
                Spacer()
                if overview { Button("See all") { tab = 1 }.frame(minHeight: 44) }
            }
            if values.isEmpty { Text("No matching Instances.").foregroundStyle(.secondary) }
            ForEach(values) { instance in
                if let index = instances.firstIndex(where: { $0.id == instance.id }) {
                    NavigationLink { InstanceDetailView(instance: $instances[index]) } label: {
                        CloudInstanceRow(name: instance.name, subtitle: "\(instance.type) · \(instance.city)", status: instance.running ? "Running" : "Stopped")
                    }.buttonStyle(.plain).accessibilityIdentifier("instance-\(instance.id)")
                    Divider()
                }
            }
        }
    }
    private var categories: some View {
        let value = Spending.sample(for: project)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Where it goes").font(.title2.bold())
            ForEach([("Compute", value.compute), ("Storage", value.storage), ("Network", value.network)], id: \.0) { item in
                HStack { Text(item.0); Spacer(); Text(Spending.euros(item.1)).monospacedDigit() }.frame(minHeight: 44)
                Divider()
            }
        }
    }
    private var history: some View {
        let months = ["Jun", "Jul", "Aug", "Sep", "Oct", "Nov"]
        let cents = [1540, 2210, 1860, 2950, 3620, 4280]
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Monthly history").font(.headline); Spacer(); Text("EUR").font(.caption).foregroundStyle(.secondary) }
            Chart(months.indices, id: \.self) { i in
                BarMark(x: .value("Month", months[i]), y: .value("EUR", Double(cents[i]) / 100))
                    .foregroundStyle(i == 5 ? palette.accent : palette.accent.opacity(0.25))
                    .accessibilityLabel(months[i]).accessibilityValue(Spending.euros(cents[i]))
            }.chartYScale(domain: 0...50).frame(height: 180)
            Text("November is month-to-date · sample history").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private var projectSpending: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By project").font(.title2.bold())
            ForEach([Project.production, .personal].filter { project == .all || $0 == project }) { item in
                Button { project = item } label: {
                    HStack { Text(item.rawValue); Spacer(); Text(Spending.euros(Spending.sample(for: item).total)).monospacedDigit() }.frame(minHeight: 44)
                }
            }
        }
    }
    private var demoAccount: some View {
        NavigationStack {
            List {
                Section { Label("Demo mode · sample data", systemImage: "cloud") }
                Section { NavigationLink { AppearanceView() } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }.accessibilityIdentifier("appearanceSettings") }
                Section { Button("Connect account") { account = false; onConnect() }.accessibilityIdentifier("openAPIConnection") }
                Section { Text("Free and open source · MPL 2.0").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden).background(palette.canvas).navigationTitle("Account")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { account = false } } }
        }
    }
    private var demoFilters: some View {
        NavigationStack {
            Form {
                Picker("Zone", selection: $zone) { Text("All zones").tag(""); ForEach(CloudAPI.zones, id: \.self) { Text($0).tag($0) } }
                Picker("Status", selection: $status) { Text("Any status").tag(""); Text("Running").tag("running"); Text("Stopped").tag("stopped") }
                Button("Reset filters") { zone = ""; status = ""; search = ""; project = .all }
            }.scrollContentBackground(.hidden).background(palette.canvas).navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { filters = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

struct InstanceDetailView: View {
    @Binding var instance: CloudInstance
    @Environment(\.themePalette) private var palette
    @State private var action: String?
    @State private var result: String?

    var body: some View {
        List {
            Section(instance.project.rawValue) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.footnote).foregroundStyle(.secondary)
                    Text(instance.name).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("instanceDetailName")
                }
                LabeledContent("Status", value: instance.running ? "Running" : "Stopped")
                LabeledContent("Location", value: instance.zone)
                LabeledContent("Instance type", value: instance.type)
                LabeledContent("Compute", value: "\(instance.cpu) vCPUs · \(instance.memoryGB) GB")
            }
            Section {
                if instance.running {
                    Button("Simulate restart", systemImage: "arrow.clockwise") { action = "restart" }
                    Button("Simulate stop", systemImage: "stop", role: .destructive) { action = "stop" }
                } else {
                    Button("Simulate start", systemImage: "power") { action = "start" }
                }
            } footer: {
                Text("Demo controls only. No cloud resource will be changed.")
            }
            if let result { Text(result).font(.footnote).foregroundStyle(.secondary) }
        }
        .scrollContentBackground(.hidden).background(palette.canvas)
        .navigationTitle(instance.name).navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Simulate \(action ?? "action") for \(instance.name)?", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
            if let action {
                Button("Simulate \(action)", role: action == "stop" ? .destructive : nil) {
                    instance.running = action != "stop"
                    result = "Demo: \(action) completed."
                    self.action = nil
                }
            }
            Button("Cancel", role: .cancel) { action = nil }
        } message: {
            Text("This changes sample data on this device only.")
        }
    }
}
