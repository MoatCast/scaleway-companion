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
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "cloud").font(.largeTitle).foregroundStyle(Theme.muted)
                        Text(store.connected ? "Your cloud account" : "Connect your cloud").font(.title2.weight(.semibold))
                        Text("Connect with a restricted Scaleway API key. Your key stays in this iPhone’s secure storage and goes directly to Scaleway.")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                Section {
                    Button(store.connected ? "Set up a read-only connection" : "Continue with Scaleway") { showBrowserSetup = true }
                        .disabled(store.busy).accessibilityIdentifier("browserSetup")
                    if !store.connected { Text("Sign in on Scaleway’s website and approve a dedicated restricted key.").font(.footnote).foregroundStyle(.secondary) }
                }
                if store.connected {
                    Section("Connected organization") {
                        Text(store.organization ?? "").font(.footnote.monospaced()).textSelection(.enabled)
                        Text("The key is stored in Keychain and is never displayed here.").font(.footnote).foregroundStyle(.secondary)
                        Button("Disconnect", role: .destructive) { confirmDisconnect = true }.disabled(store.busy)
                    }
                } else {
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
                Section {
                    Text("Free and open source · MPL 2.0\nIndependent app, not affiliated with Scaleway.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
