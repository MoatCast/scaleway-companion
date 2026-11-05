// SPDX-License-Identifier: MPL-2.0
import SwiftUI

#if DEBUG
struct LoginExperimentView: View {
    let organization: String
    @StateObject private var login = BrowserLogin()
    @Environment(\.themePalette) private var palette

    var body: some View {
        Form {
            Section {
                Text("Sign in on Scaleway’s website using your existing passkey, password or configured MFA. Your password stays on their page.")
                Text("This unsupported flow may be rejected or changed by Scaleway. No permission-approval step or automatic setup is provided by this experiment.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Handoff and verification") {
                Label(login.callbackReceived ? "Callback received on this iPhone" : "Callback not received", systemImage: login.callbackReceived ? "checkmark.circle" : "circle")
                if let expiration = login.verifiedUntil {
                    Label("Session identity and expiry verified", systemImage: "checkmark.shield")
                    Text("Expires \(expiration.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                } else { Label("Session not verified", systemImage: "circle") }
                status
            }
            Section("Read-only API checks") {
                LabeledContent("Instances · Paris 1", value: login.instances?.description ?? "Not checked")
                LabeledContent("Current-month consumption", value: login.spending?.description ?? "Not checked")
                Text("One record per endpoint, using your connected Organization ID. An empty result can verify access; it does not prove access to every project or zone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                if login.busy {
                    Button("Cancel sign-in", role: .cancel) { login.cancel() }
                } else {
                    Button("Continue with Scaleway") { login.start(organization: organization) }
                        .accessibilityIdentifier("startLogin")
                }
                if login.phase == .cancelled || login.phase == .timedOut {
                    Button("The page showed ‘Invalid app to redirect’") { login.reportRedirectRejection() }
                }
            }
            Section {
                Text("Your existing API-key connection stays active. No keys or policies are created. Temporary session tokens are held only in memory and discarded when the experiment ends. This does not sign you out of Scaleway elsewhere.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden).background(palette.canvas)
        .navigationTitle("Browser sign-in experiment").navigationBarTitleDisplayMode(.inline)
        .onDisappear { login.cancel() }
    }

    @ViewBuilder private var status: some View {
        switch login.phase {
        case .idle: EmptyView()
        case .opening: HStack { ProgressView(); Text("Waiting for browser sign-in…") }
        case .verifying: HStack { ProgressView(); Text("Verifying the returned session…") }
        case .checkingAPI: HStack { ProgressView(); Text("Checking API capabilities…") }
        case .completed:
            Text(login.instances == .verified && login.spending == .verified ? "Experiment passed. Both API reads succeeded." : "Session verified; some API access was not verified.")
                .accessibilityIdentifier("loginVerified")
        case .failed(let message): Text(message).foregroundStyle(.orange).accessibilityIdentifier("loginFailed")
        case .cancelled: Text("Sign-in cancelled.").accessibilityIdentifier("loginCancelled")
        case .timedOut: Text("Timed out without completing verification. A loaded browser page does not verify sign-in.").foregroundStyle(.orange)
        case .redirectRejected: Text("Redirect rejection reported from the browser page. This callback is not accepted by Scaleway.").foregroundStyle(.orange)
        }
    }
}
#endif
