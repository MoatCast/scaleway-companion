// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct LoginExperimentView: View {
    @ObservedObject var login: BrowserLogin
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "cloud")
                        .font(.system(size: 38, weight: .light)).foregroundStyle(Theme.purple)
                        .frame(width: 84, height: 84)
                        .glassEffect(.regular.tint(Theme.purple.opacity(0.12)), in: .rect(cornerRadius: 26))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your cloud.\nA little closer.").font(.largeTitle.bold())
                        Text("Sign in on Scaleway’s own website. Your password stays there.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Login experiment", systemImage: "flask").font(.headline)
                        Text("We’re testing whether Scaleway can return a session to this iPhone app. Mobile callback support is not yet confirmed.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Label("No API keys created", systemImage: "key")
                        Label("Session checked, then discarded", systemImage: "lock.shield")
                        Label("Dashboard stays in demo mode", systemImage: "square.grid.2x2")
                    }
                    .font(.subheadline).padding(20)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
                    status
                    if login.busy {
                        Button("Cancel sign-in", role: .cancel) { login.cancel() }
                            .buttonStyle(.glass).frame(maxWidth: .infinity)
                    } else {
                        Button { login.start() } label: {
                            Label("Continue with Scaleway", systemImage: "arrow.up.right")
                                .fontWeight(.semibold).frame(maxWidth: .infinity).frame(minHeight: 42)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("startLogin")
                    }
                    Text("Unofficial prototype. This experiment checks access with one read-only API request. No credentials are saved on this device. Clearing the result does not sign you out of Scaleway elsewhere.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Connect account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { login.cancel(); dismiss() } } }
            .onDisappear { login.cancel() }
        }
    }

    @ViewBuilder private var status: some View {
        switch login.phase {
        case .idle:
            EmptyView()
        case .opening:
            HStack { ProgressView(); Text("Waiting for Scaleway sign-in…") }.font(.subheadline)
        case .verifying:
            HStack { ProgressView(); Text("Callback received. Checking API access…") }.font(.subheadline)
        case .verified(let expiration):
            VStack(alignment: .leading, spacing: 8) {
                Label("Session verified", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                Text("Scaleway accepted the session. It expires \(expiration.formatted(date: .abbreviated, time: .shortened)). The token has been discarded; the dashboard still shows sample data.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Clear result") { login.clear() }.font(.footnote)
            }.accessibilityIdentifier("loginVerified")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Sign-in not verified", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }.accessibilityIdentifier("loginFailed")
        case .cancelled:
            Text("Sign-in cancelled. You can try again whenever you’re ready.")
                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("loginCancelled")
        }
    }
}
