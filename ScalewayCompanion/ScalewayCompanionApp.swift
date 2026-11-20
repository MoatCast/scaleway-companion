// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main
struct ScalewayCompanionApp: App {
    init() { BudgetMonitor.register() }
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .modifier(AppAppearanceModifier())
        }
    }
}

