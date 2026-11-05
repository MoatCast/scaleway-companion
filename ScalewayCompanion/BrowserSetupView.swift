// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct BrowserSetupView: View {
    @ObservedObject var store: DashboardStore
    @StateObject private var browser = BrowserLogin()
    @StateObject private var setup = AutomaticSetup()
    @State private var confirmClearRecovery = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    private var working: Bool { browser.busy || setup.busy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect with Scaleway").font(.title2.weight(.semibold))
                    Text("Sign in on Scaleway’s website, then choose what this iPhone can read. Your password and passkey stay with Scaleway.")
                    Text("Independent client. Browser sign-in is not officially supported by Scaleway and may stop working. You can always use a restricted API key instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let pending = setup.pending {
                    Section("Unfinished setup") {
                        Text("A previous attempt may have left an application or policy in Scaleway.")
                        LabeledContent("Organization", value: pending.organization).font(.footnote)
                        Text(pending.name).font(.footnote.monospaced()).textSelection(.enabled)
                        if pending.uncertain { Text("A creation request’s outcome is unknown. Check both the application and policy in Scaleway before clearing this record.").font(.footnote).foregroundStyle(.secondary) }
                        Button("Clean up this attempt") { Task { await setup.recover(store: store) } }
                            .disabled(working || (!setup.hasSession && store.setupName != pending.name))
                        Button("I checked Scaleway; clear recovery record") { confirmClearRecovery = true }.disabled(working)
                    }
                }
                if setup.invalidRecovery {
                    Section("Unfinished setup") {
                        Text("The local recovery record cannot be read. Before trying setup again, check Scaleway IAM for unfinished Companion applications and policies you created.")
                        Button("I checked Scaleway; clear recovery record") { confirmClearRecovery = true }.disabled(working)
                    }
                }
                if !setup.hasSession && setup.phase != .connected {
                    Section {
                        Button("Continue with Scaleway") {
                            browser.start { verified in await setup.prepare(verified) }
                        }.disabled(working).accessibilityIdentifier("automaticBrowserLogin")
                    }
                }
                if setup.hasSession {
                    Section("Organization") {
                        ForEach(setup.organizations) { organization in
                            Button {
                                Task { await setup.selectOrganization(organization.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(organization.name).foregroundStyle(.primary)
                                        if organization.locked { Text("Locked").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if setup.selectedOrganization == organization.id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }
                            }.disabled(working || organization.locked)
                        }
                    }
                    if setup.phase == .choosing && !setup.selectedOrganization.isEmpty {
                        Section("Projects for Instances") {
                            if setup.projects.isEmpty {
                                Text("No projects available. Use an existing restricted API key, or select another Organization.").foregroundStyle(.secondary)
                            }
                            ForEach(setup.projects) { project in
                                Button { setup.toggleProject(project.id) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(project.name).foregroundStyle(.primary)
                                            Text(project.id).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: setup.selectedProjects.contains(project.id) ? "checkmark.circle.fill" : "circle")
                                            .accessibilityLabel(setup.selectedProjects.contains(project.id) ? "Selected" : "Not selected")
                                    }
                                }.disabled(working)
                            }
                        }
                        Section("Permission summary") {
                            Label("Instances · selected projects only", systemImage: "server.rack")
                            Text("Read Instances in the \(setup.selectedProjects.count) selected project(s). No permission to start, stop, create or delete resources.")
                            Label("Billing · entire Organization", systemImage: "chart.bar")
                            Text("BillingReadOnly includes consumption and other billing information, such as invoices and payment-method information. It is broader than spending alone.")
                            Text("Creates a dedicated IAM application, one restricted policy and an application API key. The key is stored only in this iPhone’s Keychain. Your temporary website session may have broader permissions; it is discarded after setup.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if store.connected {
                                Text("Your current connection stays active until the new key is verified and saved. Its existing key is not revoked.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Button("Create read-only connection") { setup.create(store: store) }
                                .buttonStyle(SolidPrimaryButton()).disabled(!setup.canCreate || store.busy)
                                .accessibilityIdentifier("approveReadOnlySetup")
                        }
                    }
                }
                status
                if setup.cleanupWarning {
                    Section { Text("Cleanup could not be confirmed. Your previous connection is preserved. Use the unfinished-setup record above to identify and remove only this attempt’s resources in Scaleway.").foregroundStyle(.orange) }
                }
                if !working {
                    Section {
                        Button("Use an existing API key") { browser.cancel(); setup.cancel(); dismiss() }
                            .accessibilityIdentifier("manualKeyFallback")
                        Text("Disconnect in this app removes the local key. To revoke access everywhere, delete the application’s key or application in Scaleway’s IAM console.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(palette.canvas)
            .navigationTitle("Connect account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(working ? "Cancel setup" : "Done") {
                        if working { browser.cancel(); setup.cancel() } else { dismiss() }
                    }.disabled(setup.phase == .saving || setup.phase == .cleaning)
                }
            }
            .confirmationDialog("Clear this recovery record?", isPresented: $confirmClearRecovery, titleVisibility: .visible) {
                Button("I checked and removed the unfinished resources", role: .destructive) { setup.clearRecoveryAfterManualCheck() }
            } message: { Text("This clears the local record only. It does not revoke keys or delete anything in Scaleway. Continue only after checking the named application and policy there.") }
            .onChange(of: setup.phase) { _, phase in if phase == .connected { dismiss() } }
            .onDisappear { browser.cancel(); setup.cancel() }
        }
        .interactiveDismissDisabled(working)
    }

    @ViewBuilder private var status: some View {
        if browser.busy {
            Section { HStack { ProgressView(); Text(browser.phase == .verifying ? "Verifying sign-in…" : "Complete sign-in on Scaleway’s website…") } }
        } else if case .failed(let message) = browser.phase {
            Section { Text(message).foregroundStyle(.orange) }
        } else if browser.phase == .timedOut {
            Section { Text("Sign-in timed out. No connection was changed.").foregroundStyle(.orange) }
        } else if browser.phase == .cancelled && setup.phase == .idle {
            Section { Text("Sign-in cancelled.").foregroundStyle(.secondary) }
        }
        switch setup.phase {
        case .loading: Section { HStack { ProgressView(); Text("Checking available access…") } }
        case .creating: Section { HStack { ProgressView(); Text("Creating your restricted connection…") } }
        case .verifying: Section { HStack { ProgressView(); Text("Verifying read access…") }; Text("New permissions may take about a minute to apply.").font(.footnote).foregroundStyle(.secondary) }
        case .saving: Section { HStack { ProgressView(); Text("Saving securely on this iPhone…") } }
        case .cleaning: Section { HStack { ProgressView(); Text("Cleaning up this attempt…") } }
        case .failed(let message): Section { Text(message).foregroundStyle(.orange).accessibilityIdentifier("automaticSetupError") }
        case .cancelled: Section { Text("Setup cancelled. Your previous connection is preserved.").foregroundStyle(.secondary) }
        case .connected: Section { Label("Read-only connection ready", systemImage: "checkmark.shield") }
        case .idle, .choosing: EmptyView()
        }
    }
}
