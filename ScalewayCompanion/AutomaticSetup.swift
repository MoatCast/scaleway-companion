// SPDX-License-Identifier: MPL-2.0
import Foundation
import Combine

@MainActor
final class AutomaticSetup: ObservableObject {
    enum Phase: Equatable {
        case idle, loading, choosing, creating, verifying, saving, cleaning, connected, cancelled, failed(String)
    }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var organizations: [SetupOrganization] = []
    @Published private(set) var projects: [SetupProject] = []
    @Published private(set) var selectedOrganization = ""
    @Published private(set) var selectedProjects: Set<String> = []
    @Published private(set) var pending: SetupReceipt?
    @Published private(set) var cleanupWarning = false
    @Published private(set) var invalidRecovery = false
    private var session: SetupSession?
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private let api: IAMSetupAPI
    private let defaults: UserDefaults
    private let retryDelay: Duration
    private static let journalKey = "connection.pendingSetup"
    var busy: Bool { [.loading, .creating, .verifying, .saving, .cleaning].contains(phase) }
    var hasSession: Bool { session != nil }
    var canCreate: Bool { phase == .choosing && pending == nil && !invalidRecovery && !selectedOrganization.isEmpty && !selectedProjects.isEmpty }

    init(api: IAMSetupAPI = IAMSetupAPI(), defaults: UserDefaults = .standard, retryDelay: Duration = .seconds(5)) {
        self.api = api; self.defaults = defaults; self.retryDelay = retryDelay
        let data = defaults.data(forKey: Self.journalKey)
        pending = data.flatMap { try? JSONDecoder().decode(SetupReceipt.self, from: $0) }
        invalidRecovery = defaults.object(forKey: Self.journalKey) != nil && pending == nil
    }
    private func record(_ receipt: SetupReceipt?) {
        pending = receipt; invalidRecovery = false
        if let receipt, let data = try? JSONEncoder().encode(receipt) { defaults.set(data, forKey: Self.journalKey) }
        else { defaults.removeObject(forKey: Self.journalKey) }
    }
    func prepare(_ verified: SetupSession) async {
        guard !busy else { return }
        generation = UUID(); let attempt = generation
        // Bound how long the app retains a broad browser session while approval is pending.
        session = SetupSession(envelope: verified.envelope, expiresAt: min(verified.expiresAt, Date().addingTimeInterval(600)))
        expiry?.cancel()
        let seconds = max(0, session!.expiresAt.timeIntervalSinceNow)
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.session = nil
            self?.cancel()
        }
        organizations = []; projects = []; selectedOrganization = ""; selectedProjects = []
        phase = .loading
        do {
            let organizations = try await api.organizations(session: verified)
            guard generation == attempt else { return }
            self.organizations = organizations
            phase = .choosing
        } catch {
            guard generation == attempt else { return }
            session = nil; phase = .failed(message(error))
        }
    }
    func selectOrganization(_ id: String) async {
        guard !busy, let session, organizations.contains(where: { $0.id == id && !$0.locked }) else { return }
        generation = UUID(); let attempt = generation
        selectedOrganization = id; selectedProjects = []; projects = []; phase = .loading
        do {
            try await api.preflight(session: session, organization: id)
            let values = try await api.projects(session: session, organization: id)
            guard generation == attempt else { return }
            projects = values; phase = .choosing
        } catch {
            guard generation == attempt else { return }
            phase = .failed(message(error))
        }
    }
    func toggleProject(_ id: String) {
        guard phase == .choosing, projects.contains(where: { $0.id == id }) else { return }
        if !selectedProjects.insert(id).inserted { selectedProjects.remove(id) }
    }
    // Only the explicit approval action calls this method.
    func create(store: DashboardStore) {
        guard canCreate, let session else { return }
        guard defaults.data(forKey: Self.journalKey) == nil else { phase = .failed(SetupFailure.recovery.localizedDescription); return }
        let selected = selectedProjects.sorted()
        let receipt = SetupReceipt(organization: selectedOrganization)
        record(receipt); cleanupWarning = false; phase = .creating
        operation = Task { await provision(session: session, selected: selected, receipt: receipt, store: store) }
    }
    private func provision(session: SetupSession, selected: [String], receipt initial: SetupReceipt, store: DashboardStore) async {
        var receipt = initial
        do {
            guard session.expiresAt > Date() else { throw SetupFailure.expired }
            try await api.preflight(session: session, organization: receipt.organization)
            let fresh = try await api.projects(session: session, organization: receipt.organization)
            guard !selected.isEmpty, Set(selected).isSubset(of: Set(fresh.map(\.id))) else { throw SetupFailure.invalidSelection }
            try Task.checkCancellation()
            receipt.uncertain = true; record(receipt)
            receipt.application = try await api.createApplication(session: session, receipt: receipt)
            receipt.uncertain = false; record(receipt)
            try Task.checkCancellation()
            receipt.uncertain = true; record(receipt)
            receipt.policy = try await api.createPolicy(session: session, organization: receipt.organization, projects: selected, application: receipt.application!, name: receipt.name)
            receipt.uncertain = false; record(receipt)
            try Task.checkCancellation()
            try await api.verifyPolicy(session: session, receipt: receipt, projects: selected)
            try await api.verifyNoInheritedPolicies(session: session, receipt: receipt)
            try Task.checkCancellation()
            receipt.uncertain = true; record(receipt)
            let key = try await api.createKey(session: session, application: receipt.application!, name: receipt.name)
            receipt.uncertain = false; record(receipt)
            try Task.checkCancellation()
            let candidate = try APICredentials(secret: key.secret_key, organization: receipt.organization, setupName: receipt.name)
            phase = .verifying
            for attempt in 0...12 {
                do { try await api.verifyKey(candidate, projects: selected); break }
                catch {
                    try Task.checkCancellation()
                    guard attempt < 12, error as? SetupFailure == .permissionDenied || error as? SetupFailure == .expired else { throw error }
                    try await Task.sleep(for: retryDelay)
                }
            }
            try Task.checkCancellation()
            guard session.expiresAt > Date() else { throw SetupFailure.expired }
            try await api.verifyPolicy(session: session, receipt: receipt, projects: selected)
            try await api.verifyNoInheritedPolicies(session: session, receipt: receipt)
            try Task.checkCancellation()
            phase = .saving
            try await store.adoptProvisionedConnection(candidate)
            // Saved setupName lets recovery recognize a committed key after a process interruption.
            record(nil); self.session = nil; expiry?.cancel(); phase = .connected; operation = nil
            Task { await store.refresh() }
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
            if let failure = error as? SetupFailure {
                switch failure {
                case .permissionDenied, .expired, .rejected(400), .rejected(404), .rejected(409), .rejected(422):
                    receipt.uncertain = false
                default: break
                }
            }
            record(receipt)
            phase = .cleaning
            let api = self.api
            let clean: Bool
            if receipt.application != nil || receipt.policy != nil || receipt.uncertain {
                // Cancellation must not cancel revocation/cleanup of resources already created.
                clean = await Task.detached { await api.cleanup(session: session, receipt: receipt) }.value
            } else { clean = true }
            if clean { record(nil) }
            cleanupWarning = !clean
            self.session = nil; expiry?.cancel(); operation = nil
            phase = cancelled ? .cancelled : .failed(message(error))
        }
    }
    func cancel() {
        guard phase != .saving, phase != .cleaning else { return }
        if operation != nil { operation?.cancel() }
        else {
            generation = UUID(); session = nil; expiry?.cancel()
            if phase != .connected { phase = .cancelled }
        }
    }
    func recover(store: DashboardStore) async {
        guard !busy, let pending else { return }
        // Never revoke a connection committed before the app/process was interrupted.
        if store.setupName == pending.name { record(nil); cleanupWarning = false; return }
        guard let session, organizations.contains(where: { $0.id == pending.organization && !$0.locked }) else {
            phase = .failed("Sign in to the Organization shown in the recovery record to clean up this attempt."); return
        }
        phase = .cleaning
        let clean = await api.cleanup(session: session, receipt: pending)
        if clean { record(nil) }
        cleanupWarning = !clean
        phase = clean ? .choosing : .failed("Cleanup could not be confirmed. Check the named application and policy in Scaleway before clearing the recovery record.")
    }
    func clearRecoveryAfterManualCheck() {
        guard !busy else { return }
        record(nil); cleanupWarning = false
    }
    private func message(_ error: Error) -> String {
        if let failure = error as? SetupFailure { return failure.localizedDescription }
        if let failure = error as? APIError { return failure.localizedDescription }
        return "Setup could not finish. Your previous connection has been preserved."
    }
}
