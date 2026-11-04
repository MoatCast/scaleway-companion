// SPDX-License-Identifier: MPL-2.0

import AuthenticationServices
import Combine
import UIKit

@MainActor
final class BrowserLogin: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle, opening, verifying, verified(Date), failed(String), cancelled
    }

    @Published private(set) var phase = Phase.idle
    private var session: ASWebAuthenticationSession?
    private var currentAttempt: UUID?
    private var work: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var presentation: LoginPresentation?

    var busy: Bool { phase == .opening || phase == .verifying }

    func start() {
        guard !busy else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            phase = .failed("Open the app in the foreground, then try again.")
            return
        }
        presentation = LoginPresentation(window: window)
        let attempt = LoginAttempt()
        currentAttempt = attempt.id
        phase = .opening
        let browser = ASWebAuthenticationSession(url: attempt.authorizationURL, callback: .customScheme(LoginAttempt.scheme)) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self, self.currentAttempt == attempt.id else { return }
                self.session = nil
                if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    self.finish(.cancelled)
                } else if error != nil {
                    self.finish(.failed("The browser could not finish sign-in. Retry or check whether Scaleway accepts app callbacks."))
                } else if let callbackURL {
                    self.verify(callbackURL, attempt: attempt)
                } else {
                    self.finish(.failed("No callback was returned by Scaleway."))
                }
            }
        }
        browser.presentationContextProvider = presentation
        browser.prefersEphemeralWebBrowserSession = true
        session = browser
        guard browser.start() else {
            finish(.failed("iOS could not open the authentication browser."))
            return
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled, let self, self.currentAttempt == attempt.id else { return }
            self.finish(.failed("No completed sign-in after three minutes. The mobile callback may be unsupported, or sign-in may be incomplete. You can retry."))
        }
    }

    private func verify(_ url: URL, attempt: LoginAttempt) {
        phase = .verifying
        work = Task { [weak self] in
            do {
                let envelope = try attempt.decodeCallback(url)
                let expiresAt = try await SessionVerifier.verify(envelope)
                guard let self, self.currentAttempt == attempt.id, !Task.isCancelled else { return }
                self.finish(.verified(expiresAt))
            } catch {
                guard let self, self.currentAttempt == attempt.id, !Task.isCancelled else { return }
                // Do not show raw network errors: they can contain credential-bearing URLs.
                let message = (error as? LoginFailure)?.localizedDescription
                    ?? "The callback arrived, but the verification request failed. Check your connection and retry."
                self.finish(.failed(message))
            }
        }
    }

    func cancel() { if busy { finish(.cancelled) } }
    func clear() { finish(.idle) }

    private func finish(_ result: Phase) {
        currentAttempt = nil
        timeout?.cancel()
        timeout = nil
        session?.cancel()
        session = nil
        work?.cancel()
        work = nil
        presentation = nil
        phase = result
    }
}

@MainActor
private final class LoginPresentation: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow

    init(window: UIWindow) { self.window = window }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

