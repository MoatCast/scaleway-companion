// SPDX-License-Identifier: MPL-2.0

import Foundation

enum Project: String, CaseIterable, Identifiable {
    case all = "All projects", production = "Production", personal = "Personal"
    var id: String { rawValue }
}

struct CloudInstance: Identifiable {
    let id: String
    let name: String
    let project: Project
    let city: String
    let zone: String
    let type: String
    let cpu: Int
    let memoryGB: Int
    var running: Bool
}

struct Spending {
    let compute: Int
    let storage: Int
    let network: Int
    var total: Int { compute + storage + network }

    static func sample(for project: Project) -> Spending {
        switch project {
        case .all: Spending(compute: 3120, storage: 840, network: 320)
        case .production: Spending(compute: 2840, storage: 560, network: 280)
        case .personal: Spending(compute: 280, storage: 280, network: 40)
        }
    }

    static func euros(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "en_IE")))
    }
}

enum DemoData {
    static let instances: [CloudInstance] = [
        .init(id: "api", name: "api-prod", project: .production, city: "Paris", zone: "fr-par-1", type: "DEV1-S", cpu: 2, memoryGB: 2, running: true),
        .init(id: "worker", name: "worker-01", project: .production, city: "Amsterdam", zone: "nl-ams-1", type: "DEV1-M", cpu: 3, memoryGB: 4, running: true),
        .init(id: "stage", name: "staging", project: .personal, city: "Paris", zone: "fr-par-1", type: "DEV1-S", cpu: 2, memoryGB: 2, running: false)
    ]
}

