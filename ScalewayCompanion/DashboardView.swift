// SPDX-License-Identifier: MPL-2.0

import SwiftUI

enum Theme {
    static let purple = Color(red: 0.47, green: 0.33, blue: 0.85)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct DashboardView: View {
    @State private var tab = 0
    @State private var project = Project.all
    @State private var instances = DemoData.instances
    @State private var selectedID: String?
    @State private var showLogin = false
    @StateObject private var login = BrowserLogin()

    private var filtered: [CloudInstance] {
        instances.filter { project == .all || $0.project == project }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Overview", systemImage: "square.grid.2x2", value: 0) {
                page(title: "Overview") {
                    spendingCard(showLink: true)
                    instanceSection
                }
            }
            Tab("Instances", systemImage: "server.rack", value: 1) {
                page(title: "Instances") {
                    HStack(spacing: 12) {
                        statCard("Running", count: filtered.filter(\.running).count, color: .green)
                        statCard("Stopped", count: filtered.filter { !$0.running }.count, color: .secondary)
                    }
                    instanceSection
                }
            }
            Tab("Spending", systemImage: "chart.bar.xaxis", value: 2) {
                page(title: "Spending") {
                    spendingCard(showLink: false)
                    projectSpending
                    Text("Consumption is an estimate, not a final invoice. Charges can take time to appear.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginExperimentView(login: login)
        }
        .sheet(isPresented: Binding(get: { selectedID != nil }, set: { if !$0 { selectedID = nil } })) {
            if let index = instances.firstIndex(where: { $0.id == selectedID }) {
                InstanceDetailView(instance: $instances[index])
            }
        }
    }

    private func page<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("SCALEWAY COMPANION")
                            .font(.caption2.weight(.semibold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("DEMO").font(.caption2.weight(.semibold)).tracking(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    projectPicker
                    content()
                    Text("Sample data · no cloud resources connected")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("demoNotice")
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
            }
            .background {
                Theme.canvas.overlay(alignment: .topTrailing) {
                    RadialGradient(colors: [Theme.purple.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
                }.ignoresSafeArea()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Account", systemImage: "person.crop.circle") { showLogin = true }
                        .accessibilityIdentifier("accountButton")
                }
            }
        }
    }

    private var projectPicker: some View {
        Menu {
            Picker("Project", selection: $project) {
                ForEach(Project.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.3.layers.3d").foregroundStyle(Theme.purple)
                Text(project.rawValue).foregroundStyle(.primary)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16).frame(minHeight: 46)
            .glassEffect(.regular.interactive())
        }
        .accessibilityLabel("Project: \(project.rawValue)")
        .accessibilityIdentifier("projectPicker")
    }

    private func spendingCard(showLink: Bool) -> some View {
        let spending = Spending.sample(for: project)
        let categories: [(String, Int, Color)] = [
            ("Compute", spending.compute, Theme.purple),
            ("Storage", spending.storage, Theme.purple.opacity(0.55)),
            ("Network", spending.network, Theme.purple.opacity(0.25))
        ]
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Spending this month").font(.subheadline)
                Spacer()
                Text("OCT 2026").font(.caption2)
            }.foregroundStyle(.secondary)
            Text(Spending.euros(spending.total))
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .tracking(-2).minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityIdentifier("spendingTotal")
            Text("Estimated, excl. tax · sample billing period")
                .font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                HStack(spacing: 4) {
                    ForEach(categories, id: \.0) { item in
                        Capsule().fill(item.2)
                            .frame(width: max(0, (proxy.size.width - 8) * Double(item.1) / Double(spending.total)))
                    }
                }
            }.frame(height: 7).padding(.vertical, 5).accessibilityHidden(true)
            ForEach(categories, id: \.0) { item in
                HStack(spacing: 9) {
                    Circle().fill(item.2).frame(width: 7, height: 7)
                    Text(item.0)
                    Spacer()
                    Text(Spending.euros(item.1)).fontWeight(.medium).monospacedDigit()
                }.font(.subheadline)
            }
            if showLink {
                Divider()
                Button {
                    tab = 2
                } label: {
                    HStack {
                        Text("View spending details")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 32)
                }
            }
        }
        .padding(24).background(Theme.card, in: RoundedRectangle(cornerRadius: 28))
    }

    private var instanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instances").font(.title3.weight(.semibold))
                Spacer()
                Label("\(filtered.filter(\.running).count) running", systemImage: "circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.green)
            }
            Text("All zones · sample status").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(filtered) { instance in
                    if instance.id != filtered.first?.id { Divider() }
                    Button { selectedID = instance.id } label: {
                        InstanceRow(instance: instance)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("instance-\(instance.id)")
                }
            }
            .padding(.horizontal, 16).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func statCard(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(count)").font(.largeTitle.weight(.semibold)).foregroundStyle(color)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var projectSpending: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By project").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                ForEach([Project.production, .personal].filter { project == .all || $0 == project }) { item in
                    Button {
                        project = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(Theme.purple)
                            Text(item.rawValue)
                            Spacer()
                            Text(Spending.euros(Spending.sample(for: item).total)).monospacedDigit()
                        }.font(.subheadline).padding(.vertical, 20).foregroundStyle(.primary)
                    }
                    if project == .all && item == .production { Divider() }
                }
            }.padding(.horizontal, 18).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

private struct InstanceRow: View {
    let instance: CloudInstance
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .foregroundStyle(Theme.purple).frame(width: 40, height: 40)
                .background(Theme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(instance.name).font(.subheadline.weight(.semibold))
                Text("\(instance.type) · \(instance.city)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Label(instance.running ? "Running" : "Stopped", systemImage: "circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(instance.running ? Color.green : Color.secondary)
        }.padding(.vertical, 17).frame(minHeight: 76)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct InstanceDetailView: View {
    @Binding var instance: CloudInstance
    @Environment(\.dismiss) private var dismiss
    @State private var action: String?
    @State private var result: String?

    var body: some View {
        NavigationStack {
            List {
                Section(instance.project.rawValue) {
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
            .navigationTitle(instance.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

#Preview { DashboardView() }
