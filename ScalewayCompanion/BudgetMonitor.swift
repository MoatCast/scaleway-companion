// SPDX-License-Identifier: MPL-2.0
import BackgroundTasks
import UserNotifications
import WidgetKit

/// Best-effort budget alerts: iOS decides when the refresh task runs, and billing data can lag.
enum BudgetMonitor {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "app") + ".budget" }

    /// Must run before the app finishes launching.
    static func register() {
        UNUserNotificationCenter.current().delegate = ForegroundPresenter.shared
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(task)
        }
    }
    static func schedule() {
        guard BudgetStore().settings?.enabled == true else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier); return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { await runInBackground() }
        task.expirationHandler = { work.cancel() }
        Task { await work.value; task.setTaskCompleted(success: !work.isCancelled) }
    }
    private static func runInBackground() async {
        guard BudgetStore().settings?.enabled == true,
              // Locked device: WhenUnlockedThisDeviceOnly makes this fail; skip quietly and try next time.
              let credentials = try? await KeychainCredentials().load() else { return }
        let period = DashboardStore.billingPeriod()
        guard let snapshot = try? await CloudAPI().spending(credentials: credentials, period: period), !Task.isCancelled else { return }
        let totals = BillingSummary.totals(snapshot.items)
        updateWidgetSnapshot(totals: totals, period: period, organization: credentials.organization)
        await evaluate(totals: totals, period: period, organization: credentials.organization)
    }
    /// Keeps widget spend current between app launches; Instance counts stay as last seen in the app.
    private static func updateWidgetSnapshot(totals: [CurrencyAmount], period: String, organization: String) {
        let cache = SnapshotCache.shared
        guard let old = cache.load(), old.organization == organization else { return }
        let now = Date()
        cache.save(WidgetSnapshot(
            organization: organization, organizationName: old.organizationName, period: period,
            totals: totals.map { Money(currency: $0.currency, amount: $0.amount) },
            forecasts: totals.compactMap { t in Forecast.monthEnd(total: t.amount, currency: t.currency, period: period, now: now).map { Money(currency: t.currency, amount: $0) } },
            running: old.running, stopped: old.stopped, updatedAt: now))
        WidgetCenter.shared.reloadAllTimelines()
    }
    /// Shared by the background task and foreground refreshes.
    @MainActor static func evaluate(totals: [CurrencyAmount], period: String, organization: String) async {
        let budget = BudgetStore()
        guard let settings = budget.settings else { return }
        let result = BudgetCheck.evaluate(settings: settings, totals: totals, period: period, organization: organization, state: budget.state)
        budget.state = result.state
        guard let percent = result.alertPercent,
              let total = totals.first(where: { $0.currency == settings.currency })?.amount else { return }
        let content = UNMutableNotificationContent()
        content.title = percent >= 100 ? "Cloud budget reached" : "Cloud spend at \(percent)% of budget"
        content.body = "\(total.formatted(.currency(code: settings.currency))) of \(settings.amount.formatted(.currency(code: settings.currency))) this month · estimate"
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "budget-\(period)-\(percent)", content: content, trigger: nil))
    }
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

/// Shows budget alerts as banners even while the app is open; otherwise iOS drops them silently.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundPresenter()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
