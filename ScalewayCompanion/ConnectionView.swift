// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct DashboardView: View {
    @StateObject private var store = DashboardStore()
    @State private var demo = ProcessInfo.processInfo.arguments.contains("--demo")
    var body: some View {
        Group {
            if demo {
                DemoDashboardView { demo = false }
            } else if store.restoring {
                ProgressView("Opening your cloud…")
            } else if store.connected {
                LiveDashboardView(store: store)
            } else {
                ConnectionView(store: store, onDemo: { demo = true })
            }
        }
        .task(id: demo) { if !demo && store.restoring { await store.restore() } }
    }
}

struct ConnectionView: View {
    @ObservedObject var store: DashboardStore
    var onDemo: (() -> Void)?
    @State private var secret = ""
    @State private var organization = ""
    @State private var confirmDisconnect = false
    @State private var showBrowserSetup = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            Form {
                if store.connected {
                    ConnectedAccountSections(store: store)
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "cloud").font(.largeTitle).foregroundStyle(Theme.muted)
                            Text("Connect your cloud").font(.title2.weight(.semibold))
                            Text("Connect with a restricted Scaleway API key. Your key stays in this iPhone’s secure storage and goes directly to Scaleway.")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    Section {
                        Button("Continue with Scaleway") { showBrowserSetup = true }
                            .disabled(store.busy).accessibilityIdentifier("browserSetup")
                        Text("Sign in on Scaleway’s website and approve a dedicated restricted key.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("API connection") {
                        SecureField("Secret API key", text: $secret)
                            .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("apiSecret")
                        TextField("Organization ID", text: $organization)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("organizationID")
                        Button {
                            let value = secret
                            secret = ""
                            Task { await store.connect(secret: value, organization: organization) }
                        } label: {
                            HStack { Text("Connect"); if store.busy { Spacer(); ProgressView() } }
                        }
                        .buttonStyle(SolidPrimaryButton())
                        .disabled(store.busy || secret.isEmpty || organization.isEmpty)
                        .accessibilityIdentifier("connectAPI")
                    }
                    .disabled(store.busy)
                }
                if let error = store.connectionError {
                    Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("connectionError") }
                }
                Section {
                    NavigationLink { AppearanceView() } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }.accessibilityIdentifier("appearanceSettings")
                }
                if store.connected {
                    Section {
                        Button("Replace connection…") { showBrowserSetup = true }
                            .disabled(store.busy).accessibilityIdentifier("browserSetup")
                        Button("Disconnect", role: .destructive) { confirmDisconnect = true }.disabled(store.busy)
                    } footer: {
                        Text(store.setupName != nil
                             ? "Replacing creates a new restricted key. This connection stays active until the new one is verified."
                             : "Replacing signs in on Scaleway and creates a dedicated restricted key. To revoke this key, delete it in Scaleway’s IAM console.")
                    }
                }
                #if DEBUG
                if store.connected, let organization = store.organization {
                    Section("Development") {
                        NavigationLink("Browser sign-in experiment") {
                            LoginExperimentView(organization: organization)
                        }.accessibilityIdentifier("browserLoginExperiment")
                    }
                }
                #endif
                if !store.connected {
                    Section("Create a restricted key") {
                        Text("Create a dedicated IAM application and grant InstancesReadOnly for the projects you want to view, plus BillingReadOnly at organization scope. Copy its secret key and organization ID here.")
                        Text("BillingReadOnly can also expose other billing information, including invoices and payment methods. Grant only the access you are comfortable sharing.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Link("Create an API key", destination: URL(string: "https://www.scaleway.com/en/docs/iam/how-to/create-api-keys/")!)
                        Link("Configure IAM permissions", destination: URL(string: "https://www.scaleway.com/en/docs/iam/how-to/create-policy/")!)
                        Text("A new IAM policy can take about a minute to apply. This app only reads cloud data.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let onDemo, !store.connected {
                    Section { Button("Explore demo", action: onDemo).disabled(store.busy).accessibilityIdentifier("exploreDemo") }
                }
                OpenSourceSection()
            }
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle(store.connected ? "Account" : "Connect account")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if store.connected { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            .confirmationDialog("Disconnect this account?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { Task { await store.disconnect() } }
            } message: {
                Text("This removes the key and account data from this app. To revoke the key itself, delete it in Scaleway’s console.")
            }
            .sheet(isPresented: $showBrowserSetup) { BrowserSetupView(store: store) }
            .onDisappear { secret = "" }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.headline).foregroundStyle(.primary).textCase(nil) }
}

private struct AccessRow: View {
    let icon: String
    let title: String
    let detail: String
    var trailing: String?
    @Environment(\.themePalette) private var palette
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(palette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

struct ConnectedAccountSections: View {
    @ObservedObject var store: DashboardStore
    private var automatic: Bool { store.setupName != nil }
    private var method: String {
        let how = automatic ? "Set up with Scaleway sign-in" : "API key entered manually"
        guard let date = store.connectedAt else { return how }
        return "\(how) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
    private var instancesDetail: String {
        guard automatic else { return "Projects allowed by the key’s policy" }
        guard let names = store.projectNames, !names.isEmpty else { return "Projects selected during setup" }
        return names.joined(separator: ", ")
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Connected · read-only", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.success)
                Text(store.organizationName ?? "Scaleway Organization")
                    .font(.title.bold()).padding(.top, 6).accessibilityIdentifier("connectedOrganizationName")
                Text(store.organization ?? "").font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text(method).font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
            }
            .padding(.vertical, 8)
        }
        Section {
            AccessRow(icon: "server.rack", title: "Instances", detail: instancesDetail,
                      trailing: automatic ? store.projectNames.map { $0.count == 1 ? "1 project" : "\($0.count) projects" } : nil)
            AccessRow(icon: "chart.bar.fill", title: "Billing",
                      detail: automatic ? "Also invoices, payment methods" : "Spending, invoices, payment methods",
                      trailing: automatic ? "Whole org" : nil)
        } header: {
            SectionTitle("What this app can read")
        } footer: {
            Text(automatic ? "No permission to start, stop, create or delete resources."
                           : "This app only reads data. Access depends on the policy you attached to this key.")
        }
        if let name = store.setupName {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IAM application").font(.footnote).foregroundStyle(.secondary)
                    Text(name).font(.subheadline.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }.padding(.vertical, 2)
            } header: {
                SectionTitle("In Scaleway")
            } footer: {
                Text("To revoke access everywhere, delete this application in Scaleway’s IAM console. Disconnect only removes the key from this iPhone.")
            }
        }
    }
}

struct OpenSourceSection: View {
    @Environment(\.themePalette) private var palette
    var body: some View {
        Section {
            Link(destination: URL(string: "https://github.com/MoatCast/scaleway-companion")!) {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(palette.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View on GitHub").foregroundStyle(palette.accent)
                        // Concrete label colours: Link tints hierarchical styles with the accent.
                        Text("MoatCast/scaleway-companion").font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("githubLink")
        } header: {
            SectionTitle("Free and open source")
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cloud Companion is free, with no ads or subscriptions, and its code is public under MPL 2.0. Report a problem or suggest an idea by opening an issue, or improve the app yourself with a pull request.")
                Text("Independent app, not affiliated with Scaleway.")
            }
        }
    }
}
