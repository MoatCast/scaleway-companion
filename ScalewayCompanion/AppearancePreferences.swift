// SPDX-License-Identifier: MPL-2.0
import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case ocean, forest, amber, graphite
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    init(storedValue: String) { self = Self(rawValue: storedValue) ?? .ocean }
    var lightAccent: UInt32 {
        switch self { case .ocean: 0x1B6C80; case .forest: 0x286344; case .amber: 0x8F5B12; case .graphite: 0x4F5963 }
    }
    var darkAccent: UInt32 {
        switch self { case .ocean: 0x65AEBF; case .forest: 0x83C79E; case .amber: 0xD9AD62; case .graphite: 0xB6C0C9 }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    init(storedValue: String) { self = Self(rawValue: storedValue) ?? .system }
}
