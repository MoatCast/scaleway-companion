// SPDX-License-Identifier: MPL-2.0
// Foundation only: also compiled into the widget extension.
import Foundation

struct Money: Codable, Equatable, Sendable {
    let currency: String
    let amount: Decimal
}

/// Non-secret summary shared with widgets: no key, project IDs or Instance names.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    let organization: String
    let organizationName: String?
    let period: String
    let totals: [Money]
    let forecasts: [Money]
    let running: Int?
    let stopped: Int?
    let updatedAt: Date
}

struct SnapshotCache {
    static let key = "widget.snapshot"
    private let defaults: UserDefaults?
    /// `nil` defaults (no App Group configured) makes every call a no-op.
    init(defaults: UserDefaults?) { self.defaults = defaults }

    static var shared: SnapshotCache {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "CCAppGroup") as? String,
              group.hasPrefix("group."), !group.contains("$(") else { return SnapshotCache(defaults: nil) }
        return SnapshotCache(defaults: UserDefaults(suiteName: group))
    }
    func save(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
    func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    func clear() { defaults?.removeObject(forKey: Self.key) }
}
