// swift-tools-version: 5.9
// SPDX-License-Identifier: MPL-2.0
import PackageDescription
let package = Package(
    name: "ScalewayCompanionCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ScalewayCompanion", targets: ["ScalewayCompanion"])],
    targets: [
        .target(name: "ScalewayCompanion", path: "ScalewayCompanion",
                exclude: ["BrowserSetupView.swift", "ScalewayCompanionApp.swift", "DashboardView.swift", "LoginExperimentView.swift", "BrowserLogin.swift", "Info.plist", "ConnectionView.swift", "LiveDashboardView.swift", "Theme.swift", "SpendingHistoryView.swift", "AppearanceView.swift"],
                sources: ["AutomaticSetup.swift", "IAMSetupAPI.swift", "LoopbackCallback.swift", "SessionProbe.swift", "LoginProtocol.swift", "DemoData.swift", "CloudAPI.swift", "CredentialStore.swift", "DashboardStore.swift", "BillingSummary.swift", "AppearancePreferences.swift"]),
        .testTarget(name: "ScalewayCompanionTests", dependencies: ["ScalewayCompanion"], path: "ScalewayCompanionTests")
    ]
)
