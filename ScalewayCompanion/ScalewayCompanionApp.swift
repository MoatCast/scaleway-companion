// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main
struct ScalewayCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .tint(Theme.purple)
        }
    }
}

