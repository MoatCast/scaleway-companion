// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import WidgetKit

@main
struct CloudCompanionWidgets: WidgetBundle {
    var body: some Widget { SpendWidget() }
}

struct SpendEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads only the App Group snapshot; widgets never call the network or the Keychain.
struct SpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendEntry { SpendEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SpendEntry) -> Void) {
        completion(SpendEntry(date: .now, snapshot: SnapshotCache.shared.load() ?? (context.isPreview ? .sample : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendEntry>) -> Void) {
        let snapshot = SnapshotCache.shared.load()
        var entries = [SpendEntry(date: .now, snapshot: snapshot)]
        // Re-render at the UTC month boundary so last month's total stops reading as "this month".
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        if let next = calendar.dateInterval(of: .month, for: .now)?.end, next < .now.addingTimeInterval(3600) {
            entries.append(SpendEntry(date: next, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpendWidget", provider: SpendProvider()) { entry in
            SpendWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Cloud spend")
        .description("This month's estimated spend and month-end forecast.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct SpendWidgetView: View {
    let entry: SpendEntry
    @Environment(\.widgetFamily) private var family
    private let accent = Color(red: 0x1B / 255, green: 0x6C / 255, blue: 0x80 / 255)

    var body: some View {
        if let snapshot = entry.snapshot, let total = snapshot.totals.first {
            content(snapshot, total)
        } else {
            empty
        }
    }

    @ViewBuilder private func content(_ snapshot: WidgetSnapshot, _ total: Money) -> some View {
        let amount = total.amount.formatted(.currency(code: total.currency))
        let current = snapshot.isCurrentPeriod(now: entry.date)
        let forecast = snapshot.currentForecasts(now: entry.date).first { $0.currency == total.currency }
            .map { "On track for ~" + $0.amount.formatted(.currency(code: $0.currency).precision(.fractionLength(0))) }
        switch family {
        case .accessoryInline:
            Label(current ? "\(amount) this month" : "\(amount) in \(Self.month(snapshot.period, short: false))", systemImage: "cloud.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Cloud spend · \(Self.month(snapshot.period, short: true))").font(.headline).widgetAccentable()
                Text(amount).font(.title3.weight(.semibold)).monospacedDigit()
                if let forecast { Text(forecast).font(.caption) }
            }
        case .systemMedium:
            HStack(spacing: 16) {
                spend(snapshot, amount, forecast, more: snapshot.totals.count - 1)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    if let running = snapshot.running {
                        metric(value: "\(running)", label: "Instances running", dot: running > 0 ? .green : nil)
                    }
                    if let stopped = snapshot.stopped { metric(value: "\(stopped)", label: "Instances stopped", dot: nil) }
                }
                .frame(width: 120, alignment: .leading)
            }
        default:
            spend(snapshot, amount, forecast, more: snapshot.totals.count - 1)
        }
    }

    private func spend(_ snapshot: WidgetSnapshot, _ amount: String, _ forecast: String?, more: Int) -> some View {
        VStack(alignment: .leading) {
            Label(Self.month(snapshot.period, short: false), systemImage: "cloud.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(accent)
            Spacer(minLength: 4)
            Text(amount).font(.system(size: 28, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            if let forecast { Text(forecast).font(.caption).foregroundStyle(.secondary) }
            if more > 0 { Text("+\(more) more currency").font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            Text("Updated \(Text(snapshot.updatedAt, style: .relative)) ago").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(value: String, label: String, dot: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Cloud spend", systemImage: "cloud").font(.footnote.weight(.semibold)).foregroundStyle(accent)
            Text("Open Cloud Companion to load data").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2026-11" → "November" / "Nov" (UTC billing month).
    static func month(_ period: String, short: Bool) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "yyyy-MM"
        guard let date = parser.date(from: period) else { return period }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate(short ? "MMM" : "MMMM")
        return formatter.string(from: date)
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(organization: "", organizationName: nil, period: "2026-11",
                                       totals: [Money(currency: "EUR", amount: Decimal(string: "42.80")!)],
                                       forecasts: [Money(currency: "EUR", amount: 85)], running: 2, stopped: 1, updatedAt: .now)
}
