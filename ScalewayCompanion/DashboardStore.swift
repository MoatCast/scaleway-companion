// SPDX-License-Identifier: MPL-2.0
import Foundation
import Combine

protocol CloudService: Sendable {
    func instances(credentials: APICredentials, zone: String) async throws -> [LiveInstance]
    func spending(credentials: APICredentials, period: String) async throws -> SpendingSnapshot
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
    private var historyRequested = false
    private var credentials: APICredentials?
    private var committing = false
    var setupName: String? { credentials?.setupName }
    private var generation = UUID()
    private let api: any CloudService
    private let vault: any CredentialVault
    private let now: @Sendable () -> Date
    var organization: String? { credentials?.organization }
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
    init(api: any CloudService = CloudAPI(), vault: any CredentialVault = KeychainCredentials(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api; self.vault = vault; self.now = now
        selectedPeriod = Self.billingPeriod(now: now())
    }
    static func billingPeriod(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: now)
    }
    static func billingPeriods(now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.dateInterval(of: .month, for: now)!.start
        return (-5...0).map { billingPeriod(now: calendar.date(byAdding: .month, value: $0, to: month)!) }
    }
    func restore() async {
        let attempt = generation
        do {
            let saved = try await vault.load()
            guard generation == attempt else { return }
            credentials = saved; connected = saved != nil; restoring = false
            if saved != nil { await refresh() }
        } catch {
            guard generation == attempt else { return }
            restoring = false; connectionError = APIError.keychain.localizedDescription
        }
    }
    func connect(secret: String, organization: String) async {
        guard !busy, !connected else { return }
        restoring = false
        do { await load(try APICredentials(secret: secret, organization: organization), newConnection: true) }
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
        if historyRequested { await loadHistory(force: true) }
    }
    func loadHistory(force: Bool = false) async {
        historyRequested = true
        guard let credentials, !busy, !historyBusy, !Task.isCancelled else { return }
        let attempt = generation
        historyBusy = true
        let api = self.api
        let missing = periods.filter { period in
            let currentIsFresh = period == spending?.period && historyErrors[period] == nil
            return !currentIsFresh && (force || history[period] == nil || historyErrors[period] != nil)
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
    func disconnect() async {
        guard !committing else { return }
        generation = UUID(); busy = true; historyBusy = false
        do {
            try await vault.delete()
            credentials = nil; connected = false; restoring = false
            instances = []; spending = nil; projectID = ""; zone = ""; search = ""; statusFilter = ""
            history = [:]; historyErrors = [:]; historyRequested = false
            successfulZones = []; failedZones = [:]; zoneUpdatedAt = [:]
            refreshedAt = nil; spendingFetchedAt = nil
            instanceError = nil; spendingError = nil; connectionError = nil
        } catch { connectionError = APIError.keychain.localizedDescription }
        busy = false
    }
    private nonisolated static func fetchZones(api: any CloudService, credentials: APICredentials) async -> [String: Result<[LiveInstance], APIError>] {
        var results: [String: Result<[LiveInstance], APIError>] = [:]
        for start in stride(from: 0, to: CloudAPI.zones.count, by: 3) {
            if Task.isCancelled { break }
            let zones = Array(CloudAPI.zones[start..<min(start + 3, CloudAPI.zones.count)])
            await withTaskGroup(of: (String, Result<[LiveInstance], APIError>).self) { group in
                for zone in zones { group.addTask { (zone, await capture { try await api.instances(credentials: credentials, zone: zone) }) } }
                for await (zone, result) in group { results[zone] = result }
            }
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
