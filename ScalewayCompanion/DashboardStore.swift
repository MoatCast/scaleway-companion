// SPDX-License-Identifier: MPL-2.0
import Foundation
import Combine

protocol CloudService: Sendable {
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance]
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot
    func invoices(credentials: APICredentials) async throws -> [Invoice]
    func invoicePDF(credentials: APICredentials, id: String) async throws -> URL
}
extension CloudService {
    // Test doubles that predate invoices return none; CloudAPI implements the real call.
    func invoices(credentials: APICredentials) async throws -> [Invoice] { [] }
    func invoicePDF(credentials: APICredentials, id: String) async throws -> URL { throw APIError.invalidResponse }
}
extension CloudAPI: CloudService {}

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var restoring = true
    @Published private(set) var instances: [LiveInstance] = []
    @Published private(set) var spending: SpendingSnapshot?
    @Published private(set) var instanceError: String?
    @Published private(set) var spendingError: String?
    @Published private(set) var connectionError: String?
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var spendingFetchedAt: Date?
    @Published private(set) var successfulZones: Set<String> = []
    @Published private(set) var failedZones: [String: String] = [:]
    @Published private(set) var zoneUpdatedAt: [String: Date] = [:]
    @Published private(set) var zone = ""
    @Published var projectID = ""
    @Published var search = ""
    @Published var statusFilter = ""
    @Published var selectedPeriod = ""
    @Published private(set) var history: [String: SpendingSnapshot] = [:]
    @Published private(set) var historyErrors: [String: String] = [:]
    @Published private(set) var historyBusy = false
    @Published private(set) var invoices: [Invoice]?
    @Published private(set) var invoicesError: String?
    private var historyRequested = false
    private var credentials: APICredentials?
    private var committing = false
    var setupName: String? { credentials?.setupName }
    private var generation = UUID()
    private let api: any CloudService
    private let vault: any CredentialVault
    private let cache: SnapshotCache
    /// Called after the widget snapshot changes; the app target reloads widget timelines here.
    var onSnapshotChange: (@MainActor () -> Void)?
    private let now: @Sendable () -> Date
    var organization: String? { credentials?.organization }
    var organizationName: String? { credentials?.organizationName }
    var projectNames: [String]? { credentials?.projects.map { $0.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending } } }
    func projectName(_ id: String) -> String { credentials?.projects?[id] ?? id }
    var connectedAt: Date? { credentials?.connectedAt }
    var periods: [String] { Self.billingPeriods(now: now()) }
    var projects: [String] {
        Set(instances.map(\.project) + (spending?.items.map(\.projectID) ?? []) + history.values.flatMap { $0.items.map(\.projectID) }).filter { !$0.isEmpty }.sorted()
    }
    var projectInstances: [LiveInstance] {
        instances.filter { projectID.isEmpty || $0.project == projectID }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var visibleInstances: [LiveInstance] {
        instances.filter {
            (projectID.isEmpty || $0.project == projectID) && (zone.isEmpty || $0.zone == zone) &&
            (statusFilter.isEmpty || $0.state == statusFilter) &&
            (search.isEmpty || [$0.name, $0.id, $0.type, $0.zone].contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var visibleConsumption: [Consumption] { (spending?.items ?? []).filter { projectID.isEmpty || $0.projectID == projectID } }
    var selectedSpending: SpendingSnapshot? { history[selectedPeriod] ?? (spending?.period == selectedPeriod ? spending : nil) }
    var historyCurrencies: [String] { Set(history.values.flatMap { $0.items.map(\.value.currency) }).sorted() }
    func isZoneStale(_ value: String) -> Bool { failedZones[value] != nil }
    func historyPoints(currency: String) -> [MonthlyAmount] {
        periods.map { period in
            guard historyErrors[period] == nil, let snapshot = history[period] else { return MonthlyAmount(period: period, amount: nil) }
            let totals = BillingSummary.totals(snapshot.items, project: projectID)
            let currencyExists = snapshot.items.contains { $0.value.currency == currency }
            let amount = totals.first { $0.currency == currency }?.amount ?? ((snapshot.items.isEmpty || currencyExists) ? .zero : nil)
            return MonthlyAmount(period: period, amount: amount)
        }
    }
    init(api: any CloudService = CloudAPI(), vault: any CredentialVault = KeychainCredentials(), cache: SnapshotCache = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api; self.vault = vault; self.cache = cache; self.now = now
        selectedPeriod = Self.billingPeriod(now: now())
    }
    nonisolated static func billingPeriod(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: now)
    }
    nonisolated static func billingPeriods(now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.dateInterval(of: .month, for: now)!.start
        return (-5...0).map { billingPeriod(now: calendar.date(byAdding: .month, value: $0, to: month)!) }
    }
    private var restoreFailed = false
    func restore() async {
        let attempt = generation
        do {
            let saved = try await vault.load()
            guard generation == attempt else { return }
            credentials = saved; connected = saved != nil; restoring = false; restoreFailed = false
            if saved != nil { await refresh() }
        } catch {
            guard generation == attempt else { return }
            restoring = false; restoreFailed = true; connectionError = APIError.keychain.localizedDescription
        }
    }
    /// Called when the app returns to the foreground: retry a failed Keychain read, refresh data older than `maxAge`.
    func resume(maxAge: TimeInterval = 300) async {
        if restoreFailed { await restore(); return }
        guard connected, !busy else { return }
        if let refreshedAt, now().timeIntervalSince(refreshedAt) < maxAge { return }
        await refresh()
    }
    func connect(secret: String, organization: String) async {
        guard !busy, !connected else { return }
        restoring = false
        do { await load(try APICredentials(secret: secret, organization: organization, connectedAt: now()), newConnection: true) }
        catch { connectionError = APIError.invalidCredentials.localizedDescription }
    }
    // Saving is the commit point: cancellation/disconnect cannot revoke a key after it is saved.
    func adoptProvisionedConnection(_ candidate: APICredentials) async throws {
        guard !busy, !committing else { throw SetupFailure.busy }
        committing = true; busy = true
        defer { committing = false; busy = false }
        do { try await vault.save(candidate) }
        catch { throw APIError.keychain }
        generation = UUID()
        credentials = candidate; connected = true; restoring = false
        instances = []; spending = nil; projectID = ""; zone = ""; search = ""; statusFilter = ""
        history = [:]; historyErrors = [:]; historyBusy = false; historyRequested = false
        invoices = nil; invoicesError = nil
        clearSnapshot()
        successfulZones = []; failedZones = [:]; zoneUpdatedAt = [:]
        refreshedAt = nil; spendingFetchedAt = nil; selectedPeriod = Self.billingPeriod(now: now())
        instanceError = nil; spendingError = nil; connectionError = nil
    }
    func refresh() async {
        guard let credentials, !busy else { return }
        await load(credentials, newConnection: false)
    }
    func selectZone(_ value: String) async {
        guard value.isEmpty || CloudAPI.zones.contains(value) else { return }
        zone = value
    }
    private func load(_ candidate: APICredentials, newConnection: Bool) async {
        let attempt = UUID()
        generation = attempt
        let period = Self.billingPeriod(now: now())
        busy = true; historyBusy = false; connectionError = nil
        let api = self.api
        async let fleet = Self.fetchZones(api: api, credentials: candidate)
        async let billing = Self.capture { try await api.spending(credentials: candidate, period: period) }
        let (zones, bill) = await (fleet, billing)
        guard generation == attempt else { return }
        guard !Task.isCancelled else { busy = false; return }
        if newConnection {
            guard zones.values.contains(where: \.isSuccess) || bill.isSuccess else {
                instanceError = zones.values.compactMap(\.message).first
                spendingError = bill.message
                connectionError = instanceError ?? spendingError; busy = false
                return
            }
            do { try await vault.save(candidate) }
            catch {
                guard generation == attempt else { return }
                connectionError = APIError.keychain.localizedDescription; busy = false
                return
            }
            guard generation == attempt else { return }
            credentials = candidate; connected = true
        }
        let stamp = now()
        successfulZones = []; failedZones = [:]
        for zone in CloudAPI.zones {
            switch zones[zone] {
            case .success(let items):
                successfulZones.insert(zone)
                instances.removeAll { $0.zone == zone }
                instances += items.map { item in var value = item; value.zone = zone; return value }
                zoneUpdatedAt[zone] = stamp
            case .failure(let error): failedZones[zone] = error.localizedDescription
            case nil: failedZones[zone] = APIError.invalidResponse.localizedDescription
            }
        }
        instanceError = successfulZones.isEmpty ? failedZones.values.first : nil
        switch bill {
        case .success(let value):
            spending = value; spendingError = nil; spendingFetchedAt = stamp
            history[period] = value; historyErrors[period] = nil
        case .failure: spendingError = bill.message; historyErrors[period] = bill.message
        }
        if !periods.contains(selectedPeriod) { selectedPeriod = period }
        refreshedAt = stamp; busy = false
        writeSnapshot()
        if historyRequested { await loadHistory(force: true) }
    }
    func loadHistory(force: Bool = false) async {
        historyRequested = true
        guard let credentials, !busy, !historyBusy, !Task.isCancelled else { return }
        let attempt = generation
        historyBusy = true
        let api = self.api
        let recent = Set(periods.suffix(2))
        let missing = periods.filter { period in
            let currentIsFresh = period == spending?.period && historyErrors[period] == nil
            return !currentIsFresh && ((force && recent.contains(period)) || history[period] == nil || historyErrors[period] != nil)
        }
        for start in stride(from: 0, to: missing.count, by: 3) {
            let chunk = Array(missing[start..<min(start + 3, missing.count)])
            let results = await withTaskGroup(of: (String, Result<SpendingSnapshot, APIError>).self) { group in
                for period in chunk { group.addTask { (period, await Self.capture { try await api.spending(credentials: credentials, period: period) }) } }
                var values: [String: Result<SpendingSnapshot, APIError>] = [:]
                for await (period, result) in group { values[period] = result }
                return values
            }
            guard generation == attempt else { return }
            guard !Task.isCancelled else { historyBusy = false; return }
            for (period, result) in results {
                switch result {
                case .success(let value):
                    history[period] = value; historyErrors[period] = nil
                    if period == Self.billingPeriod(now: now()) {
                        spending = value; spendingError = nil; spendingFetchedAt = now()
                    }
                case .failure:
                    historyErrors[period] = result.message
                    if period == Self.billingPeriod(now: now()) { spendingError = result.message }
                }
            }
        }
        guard generation == attempt else { return }
        historyBusy = false
    }
    func loadInvoices() async {
        guard let credentials else { return }
        let attempt = generation
        do {
            let values = try await api.invoices(credentials: credentials)
            guard generation == attempt else { return }
            invoices = values; invoicesError = nil
        } catch {
            guard generation == attempt, !(error is CancellationError) else { return }
            invoicesError = ((error as? APIError) ?? .network).localizedDescription
        }
    }
    func invoicePDF(id: String) async throws -> URL {
        guard let credentials else { throw APIError.invalidCredentials }
        return try await api.invoicePDF(credentials: credentials, id: id)
    }
    private func writeSnapshot() {
        guard connected, let credentials, let spending else { return }
        let totals = BillingSummary.totals(spending.items)
        let haveInstances = !zoneUpdatedAt.isEmpty
        cache.save(WidgetSnapshot(
            organization: credentials.organization, organizationName: credentials.organizationName, period: spending.period,
            totals: totals.map { Money(currency: $0.currency, amount: $0.amount) },
            forecasts: totals.compactMap { total in
                Forecast.monthEnd(total: total.amount, currency: total.currency, period: spending.period, now: now()).map { Money(currency: total.currency, amount: $0) }
            },
            running: haveInstances ? instances.filter { $0.state == "running" }.count : nil,
            stopped: haveInstances ? instances.filter { $0.state != "running" }.count : nil,
            updatedAt: spendingFetchedAt ?? now()))
        onSnapshotChange?()
    }
    private func clearSnapshot() { cache.clear(); onSnapshotChange?() }
    func disconnect() async {
        guard !committing else { return }
        generation = UUID(); busy = true; historyBusy = false
        do {
            try await vault.delete()
            credentials = nil; connected = false; restoring = false
            instances = []; spending = nil; projectID = ""; zone = ""; search = ""; statusFilter = ""
            history = [:]; historyErrors = [:]; historyRequested = false
            invoices = nil; invoicesError = nil
            clearSnapshot()
            successfulZones = []; failedZones = [:]; zoneUpdatedAt = [:]
            refreshedAt = nil; spendingFetchedAt = nil
            instanceError = nil; spendingError = nil; connectionError = nil
        } catch { connectionError = APIError.keychain.localizedDescription }
        busy = false
    }
    nonisolated static let zoneConcurrency = 4
    private nonisolated static func fetchZones(api: any CloudService, credentials: APICredentials) async -> [String: Result<[LiveInstance], APIError>] {
        var results: [String: Result<[LiveInstance], APIError>] = [:]
        var pending = CloudAPI.zones[...]
        await withTaskGroup(of: (String, Result<[LiveInstance], APIError>).self) { group in
            func next() {
                guard !Task.isCancelled, let zone = pending.popFirst() else { return }
                group.addTask { (zone, await capture { try await api.instances(credentials: credentials, zone: zone) }) }
            }
            for _ in 0..<zoneConcurrency { next() }
            for await (zone, result) in group { results[zone] = result; next() }
        }
        return results
    }
    private nonisolated static func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, APIError> {
        do { return .success(try await work()) }
        catch let error as APIError { return .failure(error) }
        catch { return .failure(.network) }
    }
}
private extension Result where Failure == APIError {
    var isSuccess: Bool { if case .success = self { return true }; return false }
    var message: String? { if case .failure(let error) = self { return error.localizedDescription }; return nil }
}
