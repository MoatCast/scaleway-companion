// SPDX-License-Identifier: MPL-2.0
import AuthenticationServices
import Combine
import UIKit

@MainActor
final class BrowserLogin: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle, opening, verifying, checkingAPI, completed, failed(String), cancelled, timedOut, redirectRejected
    }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var callbackReceived = false
    @Published private(set) var verifiedUntil: Date?
    @Published private(set) var instances: SessionProbe.Outcome?
    @Published private(set) var spending: SessionProbe.Outcome?
    private var session: ASWebAuthenticationSession?
    private var receiver: LoopbackCallback?
    private var currentAttempt: UUID?
    private var handoff = LoginHandoff()
    private var work: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var presentation: LoginPresentation?

    var busy: Bool { [.opening, .verifying, .checkingAPI].contains(phase) }

    func start(organization: String? = nil, onVerified: ((SetupSession) async -> Void)? = nil) {
        guard !busy, organization == nil || UUID(uuidString: organization!) != nil, organization != nil || onVerified != nil else { return }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow) else {
            phase = .failed("Open the app in the foreground, then try again."); return
        }
        clear()
        let id = UUID()
        currentAttempt = id
        handoff = LoginHandoff()
        presentation = LoginPresentation(window: window)
        phase = .opening
        let receiver = LoopbackCallback()
        self.receiver = receiver
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            guard let self, self.currentAttempt == id else { return }
            self.finish(.timedOut)
        }
        work = Task { [weak self] in
            do {
                let attempt = try await receiver.start()
                guard let self, self.currentAttempt == id, !Task.isCancelled else { return }
                // Local HTTP completion is received independently. The registered scheme is
                // only a browser lifecycle sentinel; Scaleway never receives that redirect.
                let browser = ASWebAuthenticationSession(url: attempt.authorizationURL, callback: .customScheme(LoginAttempt.scheme)) { [weak self] _, error in
                    Task { @MainActor in
                        guard let self, self.currentAttempt == id, self.handoff.shouldCancelForBrowserDismissal(callbackAccepted: self.receiver?.callbackAccepted == true) else { return }
                        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { self.finish(.cancelled) }
                        else { self.finish(.failed("The authentication browser could not finish sign-in.")) }
                    }
                }
                browser.presentationContextProvider = self.presentation
                browser.prefersEphemeralWebBrowserSession = true
                self.session = browser
                guard browser.start() else { self.finish(.failed("iOS could not open the authentication browser.")); return }
                let envelope = try await receiver.wait()
                guard self.currentAttempt == id, !Task.isCancelled, self.handoff.acceptCallback() else { return }
                self.callbackReceived = true
                self.phase = .verifying
                // Mark receipt before dismissal; the cancellation callback must not win.
                browser.cancel()
                self.session = nil
                let expiration = try await SessionVerifier.verify(envelope)
                guard self.currentAttempt == id, !Task.isCancelled else { return }
                self.verifiedUntil = expiration
                if let onVerified {
                    // Handoff transfers ownership to setup without cancelling the receiving task.
                    self.work = nil
                    self.finish(.completed)
                    await onVerified(SetupSession(envelope: envelope, expiresAt: expiration))
                    return
                }
                guard let organization else { throw LoginFailure.invalidResponse }
                self.phase = .checkingAPI
                let probe = SessionProbe()
                self.instances = try await probe.read(.instances, envelope: envelope, organization: organization)
                guard self.currentAttempt == id, !Task.isCancelled else { return }
                guard expiration > Date() else { throw LoginFailure.expired }
                self.spending = try await probe.read(.spending, envelope: envelope, organization: organization)
                guard self.currentAttempt == id, !Task.isCancelled else { return }
                guard expiration > Date() else { throw LoginFailure.expired }
                self.finish(.completed)
                // Envelope goes out of scope here; nothing touches the saved API key.
            } catch {
                guard let self, self.currentAttempt == id, !Task.isCancelled else { return }
                if error as? LoginFailure == .timedOut { self.finish(.timedOut) }
                else if error is CancellationError { self.finish(.cancelled) }
                else {
                    self.finish(.failed((error as? LoginFailure)?.localizedDescription ?? "The verification request failed. Check your connection and try again."))
                }
            }
        }
    }

    func reportRedirectRejection() {
        if phase == .cancelled || phase == .timedOut { finish(.redirectRejected) }
    }
    func cancel() { if busy { finish(.cancelled) } }
    func clear() {
        finish(.idle)
        callbackReceived = false; verifiedUntil = nil; instances = nil; spending = nil
    }
    private func finish(_ result: Phase) {
        handoff.finish()
        currentAttempt = nil
        timeout?.cancel(); timeout = nil
        receiver?.cancel(); receiver = nil
        session?.cancel(); session = nil
        work?.cancel(); work = nil
        presentation = nil
        phase = result
    }
}

@MainActor
private final class LoginPresentation: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
