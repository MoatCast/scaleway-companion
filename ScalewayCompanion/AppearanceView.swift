// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct AppearanceView: View {
    @AppStorage("appearance.theme") private var theme = AppTheme.ocean.rawValue
    @AppStorage("appearance.mode") private var mode = AppAppearance.system.rawValue
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        List {
            Section("Display") {
                Picker("Display", selection: Binding(get: { AppAppearance(storedValue: mode).rawValue }, set: { mode = $0 })) {
                    ForEach(AppAppearance.allCases) { Text($0.name).tag($0.rawValue) }
                }.pickerStyle(.segmented).accessibilityIdentifier("appearanceMode")
            }
            Section {
                ForEach(AppTheme.allCases) { choice in
                    Button { theme = choice.rawValue } label: {
                        HStack(spacing: 12) {
                            Circle().fill(Theme.color(palette.dark ? choice.darkAccent : choice.lightAccent)).frame(width: 22, height: 22).accessibilityHidden(true)
                            Text(choice.name).foregroundStyle(Theme.ink)
                            Spacer()
                            if AppTheme(storedValue: theme) == choice { Image(systemName: "checkmark").fontWeight(.semibold) }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("theme-\(choice.rawValue)")
                    .accessibilityAddTraits(AppTheme(storedValue: theme) == choice ? .isSelected : [])
                }
            } header: { Text("Colour theme") } footer: { Text("Choose a subtle accent throughout the app.") }
            Section {
                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("This month").foregroundStyle(.secondary)
                        Spacer()
                        Text(Spending.euros(4280)).font(.title.weight(.semibold)).monospacedDigit()
                    }
                    if opaque { previewTabs.background(Theme.card, in: Capsule()) }
                    else { previewTabs.glassEffect(.regular) }
                }.padding(.vertical, 8)
            } header: { Text("Preview") } footer: { Text("Sample data. Changes apply immediately and stay on this device.") }
        }
        .scrollContentBackground(.hidden).background(palette.canvas)
        .navigationTitle("Appearance").navigationBarTitleDisplayMode(.large)
    }
    private var previewTabs: some View {
        HStack(spacing: 0) {
            ForEach(["Overview", "Instances", "Spending"], id: \.self) { title in
                Text(title).font(.caption).fontWeight(title == "Overview" ? .semibold : .regular)
                    .foregroundStyle(title == "Overview" ? palette.accent : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(title == "Overview" ? palette.raised : .clear, in: Capsule())
            }
        }.padding(4).accessibilityElement(children: .ignore).accessibilityLabel("Preview of \(AppTheme(storedValue: theme).name) theme")
    }
}
