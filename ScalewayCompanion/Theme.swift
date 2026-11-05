// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import UIKit

enum Theme {
    static let canvas = adaptive(0xF5F6F8, 0x000000)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let line = Color(uiColor: .separator)
    static let raised = Color(uiColor: .tertiarySystemGroupedBackground)
    static let accent = adaptive(0x1B6C80, 0x65AEBF)
    static let success = adaptive(0x1E7B4F, 0x83C79E)
    static let danger = adaptive(0xC4242A, 0xF28B8E)
    static func color(_ hex: UInt32) -> Color { Color(uiColor: uiColor(hex)) }
    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in uiColor(traits.userInterfaceStyle == .dark ? dark : light) })
    }
}

struct ThemePalette {
    var theme = AppTheme.ocean
    var dark = false
    var increasedContrast = false
    var accent: Color { Theme.color(dark ? theme.darkAccent : theme.lightAccent) }
    var canvas: Color {
        let hex: UInt32
        if dark { hex = 0x000000 } else {
            switch theme { case .ocean: hex = 0xF5F6F8; case .forest: hex = 0xF2F6F3; case .amber: hex = 0xF8F6F1; case .graphite: hex = 0xF4F5F6 }
        }
        return Theme.color(hex)
    }
    var raised: Color { accent.opacity(dark ? 0.13 : 0.07) }
    var line: Color { increasedContrast ? Color.primary.opacity(0.55) : Theme.line.opacity(0.45) }
}
private struct ThemePaletteKey: EnvironmentKey { static let defaultValue = ThemePalette() }
extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

struct AppAppearanceModifier: ViewModifier {
    @AppStorage("appearance.theme") private var theme = AppTheme.ocean.rawValue
    @AppStorage("appearance.mode") private var mode = AppAppearance.system.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let choice = AppAppearance(storedValue: mode)
        let scheme: ColorScheme? = choice == .system ? nil : (choice == .dark ? .dark : .light)
        let palette = ThemePalette(theme: AppTheme(storedValue: theme), dark: (scheme ?? systemScheme) == .dark, increasedContrast: contrast == .increased)
        content.environment(\.themePalette, palette).tint(palette.accent).preferredColorScheme(scheme)
    }
}

struct SolidPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themePalette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isEnabled ? (palette.dark ? Color.black : Color.white) : Color.secondary)
            .background(isEnabled ? palette.accent : Color(uiColor: .tertiarySystemFill), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct CompactGlassButton: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.themePalette) private var palette
    @ViewBuilder func body(content: Content) -> some View {
        if opaque {
            content.buttonStyle(.bordered).background(Theme.card, in: Capsule()).overlay(Capsule().stroke(palette.line))
        } else { content.buttonStyle(.glass) }
    }
}

struct CloudInstanceRow: View {
    let name: String
    let subtitle: String
    let status: String
    var stale: String? = nil
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let statusColor = status.lowercased() == "running" && stale == nil ? Theme.success : Theme.muted
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                if textSize.isAccessibilitySize { Text(status).font(.body).foregroundStyle(statusColor) }
                if let stale { Text(stale).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !textSize.isAccessibilitySize { Text(status).font(.footnote).foregroundStyle(statusColor).fixedSize() }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .frame(minHeight: 76).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct FleetSummary: View {
    let running: String
    let coverage: String
    @Environment(\.themePalette) private var palette
    var body: some View {
        HStack(spacing: 16) {
            metric(running, "Running")
            Rectangle().fill(palette.line).frame(width: 1)
            metric(coverage, "Zones checked")
        }.fixedSize(horizontal: false, vertical: true).padding(16)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 20))
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct ConsumptionStrip: View {
    let amounts: [Decimal]
    @Environment(\.themePalette) private var palette
    var body: some View {
        // Credits and mixed-sign categories have no meaningful positive part-to-whole strip.
        if !amounts.isEmpty, amounts.allSatisfy({ $0 >= 0 }), amounts.reduce(0, +) > 0 {
            let values = amounts.filter { $0 > 0 }
            let total = NSDecimalNumber(decimal: values.reduce(0, +)).doubleValue
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, amount in
                        Capsule().fill(palette.accent.opacity(index == 0 ? 1 : (index == 1 ? 0.45 : 0.22)))
                            .frame(width: max(0, geometry.size.width - CGFloat(values.count - 1) * 3) * NSDecimalNumber(decimal: amount).doubleValue / total)
                    }
                }
            }.frame(height: 5).accessibilityHidden(true)
        }
    }
}
