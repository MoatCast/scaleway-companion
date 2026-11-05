// SPDX-License-Identifier: MPL-2.0
import Foundation

struct SetupSession {
    let envelope: SessionEnvelope
    let expiresAt: Date
}
struct SetupOrganization: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let locked: Bool
}
struct SetupProject: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let organization_id: String
}
struct SetupReceipt: Codable, Equatable {
    let organization: String
    let name: String
    var application: String?
    var policy: String?
    var uncertain = false
    init(organization: String) {
        self.organization = organization
        name = "Companion-" + UUID().uuidString.lowercased()
    }
}
enum SetupFailure: Error, LocalizedError, Equatable {
    case invalidResponse, invalidSelection, permissionDenied, expired, network, rejected(Int), verification, inheritedAccess, recovery, busy
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Scaleway returned an unexpected setup response."
        case .invalidSelection: "Choose an Organization and at least one of its projects."
        case .permissionDenied: "This sign-in cannot create and manage the required IAM application and policy in this Organization. You can use an existing restricted API key instead."
        case .expired: "Your temporary sign-in expired. Sign in again to continue."
        case .network: "The setup request could not finish. Check your connection."
        case .rejected(let status): "Scaleway rejected the setup request (HTTP \(status))."
        case .verification: "The requested permissions and read access could not be verified."
        case .inheritedAccess: "Other Organization policies also apply to this application. Automatic setup cannot guarantee the requested restricted access. No existing policies were changed; use a separately restricted API key instead."
        case .recovery: "A previous setup needs cleanup before creating another connection."
        case .busy: "Wait for the current account update to finish, then try again."
        }
    }
}

struct IAMSetupAPI: Sendable {
    private let transport: CloudAPI.Transport
    init(transport: @escaping CloudAPI.Transport = { try await CloudAPI.send($0) }) { self.transport = transport }
    private func uuid(_ value: String) throws {
        guard UUID(uuidString: value) != nil else { throw SetupFailure.invalidResponse }
    }
    private func send(_ method: String, path: String, session: SetupSession? = nil, key: String? = nil,
                      query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        try Task.checkCancellation()
        var url = URLComponents(string: "https://api.scaleway.com")!
        guard path.hasPrefix("/"), !path.contains(".."), !path.contains(":"), !path.contains("?") else { throw SetupFailure.invalidResponse }
        url.path = path; url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        if let session {
            guard session.expiresAt > Date() else { throw SetupFailure.expired }
            try session.envelope.validate()
            request.setValue(session.envelope.token, forHTTPHeaderField: "X-Session-Token")
        } else if let key {
            guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw SetupFailure.invalidResponse }
            request.setValue(key, forHTTPHeaderField: "X-Auth-Token")
        } else { throw SetupFailure.invalidResponse }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await transport(request)
            // A successful POST must be decoded and journaled even if cancellation arrived.
            guard response.url == request.url, data.count <= 2_000_000 else { throw SetupFailure.invalidResponse }
            switch response.statusCode {
            case 200, 201, 204: return data
            case 401: throw SetupFailure.expired
            case 403: throw SetupFailure.permissionDenied
            default: throw SetupFailure.rejected(response.statusCode)
            }
        } catch let failure as SetupFailure { throw failure }
        catch { throw SetupFailure.network }
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw SetupFailure.invalidResponse }
        return value
    }
    func organizations(session: SetupSession) async throws -> [SetupOrganization] {
        try uuid(session.envelope.jwt.audienceId)
        struct Response: Decodable {
            struct Connection: Decodable { let organization: SetupOrganization }
            let connections: [Connection]
        }
        let response = try decode(Response.self, await send("GET", path: "/iam/v1alpha1/users/\(session.envelope.jwt.audienceId)/connections", session: session))
        let values = response.connections.map(\.organization)
        guard !values.isEmpty, Set(values.map(\.id)).count == values.count else { throw SetupFailure.invalidResponse }
        for value in values { try uuid(value.id) }
        return values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func projects(session: SetupSession, organization: String) async throws -> [SetupProject] {
        try uuid(organization)
        struct Response: Decodable { let projects: [SetupProject]; let total_count: Int }
        var values: [SetupProject] = []
        for page in 1...100 {
            let response = try decode(Response.self, await send("GET", path: "/account/v3/projects", session: session, query: [
                .init(name: "organization_id", value: organization), .init(name: "page", value: String(page)), .init(name: "page_size", value: "100")]))
            for project in response.projects {
                try uuid(project.id)
                guard project.organization_id.lowercased() == organization.lowercased() else { throw SetupFailure.invalidResponse }
            }
            values += response.projects
            guard response.total_count >= values.count, Set(values.map(\.id)).count == values.count else { throw SetupFailure.invalidResponse }
            if values.count == response.total_count { return values }
            guard !response.projects.isEmpty else { throw SetupFailure.invalidResponse }
        }
        throw SetupFailure.invalidResponse
    }
    func preflight(session: SetupSession, organization: String) async throws {
        try uuid(organization)
        let permissions = ["application", "policy", "api_key"].flatMap { name in
            ["create", "delete"].map { ["service": "iam", "name": name, "action": $0, "organization_id": organization] }
        }
        struct Response: Decodable { struct Decision: Decodable { let decision: String }; let responses: [Decision] }
        let response = try decode(Response.self, await send("POST", path: "/iam/v1alpha1/check-permissions", session: session, body: ["permissions": permissions]))
        guard response.responses.count == permissions.count, response.responses.allSatisfy({ $0.decision == "allow" }) else { throw SetupFailure.permissionDenied }
    }
    struct Resource: Decodable {
        let id: String
        let organization_id: String
        let name: String
        let application_id: String?
        let group_id: String?
        let user_id: String?
        let no_principal: Bool?
    }
    func createApplication(session: SetupSession, receipt: SetupReceipt) async throws -> String {
        try uuid(receipt.organization)
        let resource = try decode(Resource.self, await send("POST", path: "/iam/v1alpha1/applications", session: session, body: [
            "name": receipt.name, "organization_id": receipt.organization, "description": "Read-only iPhone companion connection", "tags": [receipt.name]]))
        try uuid(resource.id)
        guard resource.name == receipt.name, resource.organization_id == receipt.organization else { throw SetupFailure.invalidResponse }
        return resource.id
    }
    func createPolicy(session: SetupSession, organization: String, projects: [String], application: String, name: String) async throws -> String {
        try uuid(organization); try uuid(application)
        guard !projects.isEmpty, Set(projects).count == projects.count, projects.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw SetupFailure.invalidSelection }
        let rules: [[String: Any]] = [
            ["permission_set_names": ["InstancesReadOnly"], "project_ids": projects],
            ["permission_set_names": ["BillingReadOnly"], "organization_id": organization]]
        let resource = try decode(Resource.self, await send("POST", path: "/iam/v1alpha1/policies", session: session, body: [
            "name": name, "organization_id": organization, "application_id": application,
            "description": "Instances on chosen projects and Organization billing, read only", "tags": [name], "rules": rules]))
        try uuid(resource.id)
        guard resource.name == name, resource.organization_id == organization, resource.application_id == application else { throw SetupFailure.invalidResponse }
        return resource.id
    }
    struct Key: Decodable {
        let access_key: String
        let secret_key: String
        let application_id: String
        let user_id: String?
    }
    func createKey(session: SetupSession, application: String, name: String) async throws -> Key {
        try uuid(application)
        let key = try decode(Key.self, await send("POST", path: "/iam/v1alpha1/api-keys", session: session,
                                                body: ["application_id": application, "description": name]))
        guard key.application_id == application, key.user_id == nil, !key.access_key.isEmpty else { throw SetupFailure.invalidResponse }
        _ = try APICredentials(secret: key.secret_key, organization: UUID().uuidString)
        return key
    }
    func verifyPolicy(session: SetupSession, receipt: SetupReceipt, projects: [String]) async throws {
        guard let id = receipt.policy, let app = receipt.application else { throw SetupFailure.invalidResponse }
        try uuid(id); try uuid(app)
        let policy = try decode(Resource.self, await send("GET", path: "/iam/v1alpha1/policies/\(id)", session: session))
        guard policy.id == id, policy.name == receipt.name, policy.organization_id == receipt.organization, policy.application_id == app else { throw SetupFailure.verification }
        struct Rules: Decodable {
            struct Rule: Decodable {
                let permission_set_names: [String]
                let project_ids: [String]?
                let organization_id: String?
                let condition: String?
                let deny: Bool?
                let account_root_user_id: String?
            }
            let rules: [Rule]
            let total_count: Int
        }
        let response = try decode(Rules.self, await send("GET", path: "/iam/v1alpha1/rules", session: session, query: [.init(name: "policy_id", value: id), .init(name: "page_size", value: "100")]))
        guard response.total_count == 2, response.rules.count == 2 else { throw SetupFailure.verification }
        let compute = response.rules.filter { $0.permission_set_names == ["InstancesReadOnly"] }
        let billing = response.rules.filter { $0.permission_set_names == ["BillingReadOnly"] }
        guard compute.count == 1, billing.count == 1,
              Set(compute[0].project_ids ?? []) == Set(projects), compute[0].project_ids?.count == projects.count,
              compute[0].organization_id == nil, (billing[0].project_ids ?? []).isEmpty,
              billing[0].organization_id == receipt.organization,
              response.rules.allSatisfy({ ($0.condition ?? "").isEmpty && $0.deny != true && $0.account_root_user_id == nil }) else { throw SetupFailure.verification }
    }
    func verifyNoInheritedPolicies(session: SetupSession, receipt: SetupReceipt) async throws {
        guard let application = receipt.application, let expectedPolicy = receipt.policy else { throw SetupFailure.verification }
        struct Groups: Decodable {
            struct Group: Decodable {
                let id: String
                let organization_id: String
                let application_ids: [String]?
                let all_applications: Bool?
                let managed: Bool?
            }
            let groups: [Group]
            let total_count: Int
        }
        var memberships: Set<String> = []
        var groupCount = 0
        var groupsComplete = false
        for page in 1...100 {
            let response = try decode(Groups.self, await send("GET", path: "/iam/v1alpha1/groups", session: session, query: [
                .init(name: "organization_id", value: receipt.organization), .init(name: "page", value: String(page)), .init(name: "page_size", value: "100")]))
            for group in response.groups {
                try uuid(group.id)
                guard group.organization_id == receipt.organization,
                      !(group.managed == true && group.all_applications == nil) else { throw SetupFailure.verification }
                if group.all_applications == true || (group.application_ids ?? []).contains(application) { memberships.insert(group.id) }
            }
            groupCount += response.groups.count
            guard groupCount <= response.total_count else { throw SetupFailure.invalidResponse }
            if groupCount == response.total_count { groupsComplete = true; break }
            guard !response.groups.isEmpty else { throw SetupFailure.invalidResponse }
        }
        guard groupsComplete else { throw SetupFailure.invalidResponse }
        struct Policies: Decodable { let policies: [Resource]; let total_count: Int }
        var count = 0
        var relevant: [String] = []
        for page in 1...100 {
            let response = try decode(Policies.self, await send("GET", path: "/iam/v1alpha1/policies", session: session, query: [
                .init(name: "organization_id", value: receipt.organization), .init(name: "page", value: String(page)), .init(name: "page_size", value: "100")]))
            for policy in response.policies {
                guard policy.organization_id == receipt.organization else { throw SetupFailure.verification }
                let principals = [policy.application_id, policy.group_id, policy.user_id].compactMap { $0 }.filter { !$0.isEmpty }
                guard principals.count == 1 || (principals.isEmpty && policy.no_principal == true) else { throw SetupFailure.verification }
                if policy.application_id == application || memberships.contains(policy.group_id ?? "") { relevant.append(policy.id) }
            }
            count += response.policies.count
            guard count <= response.total_count else { throw SetupFailure.invalidResponse }
            if count == response.total_count {
                guard relevant == [expectedPolicy] else { throw SetupFailure.inheritedAccess }
                return
            }
            guard !response.policies.isEmpty else { throw SetupFailure.invalidResponse }
        }
        throw SetupFailure.invalidResponse
    }
    func verifyKey(_ credentials: APICredentials, projects: [String]) async throws {
        // Readback proves exact scopes; separate project-filtered requests check each selected scope.
        struct Instances: Decodable { let servers: [LiveInstance] }
        for project in projects {
            try uuid(project)
            let data = try await send("GET", path: "/instance/v1/zones/fr-par-1/servers", key: credentials.secret, query: [
                .init(name: "project", value: project), .init(name: "organization", value: credentials.organization), .init(name: "per_page", value: "1"), .init(name: "page", value: "1")])
            let response = try decode(Instances.self, data)
            guard response.servers.allSatisfy({ $0.project == project }) else { throw SetupFailure.verification }
        }
        struct ConsumptionPage: Decodable { let consumptions: [Consumption] }
        _ = try decode(ConsumptionPage.self, await send("GET", path: "/billing/v2beta1/consumptions", key: credentials.secret, query: [
            .init(name: "organization_id", value: credentials.organization), .init(name: "billing_period", value: DashboardStore.billingPeriod()), .init(name: "page_size", value: "1"), .init(name: "page", value: "1")]))
    }
    func cleanup(session: SetupSession, receipt: SetupReceipt) async -> Bool {
        struct Applications: Decodable { let applications: [Resource]; let total_count: Int }
        struct Policies: Decodable { let policies: [Resource]; let total_count: Int }
        func remove(_ resource: Resource, kind: String) async throws {
            try uuid(resource.id)
            guard resource.name == receipt.name, resource.organization_id == receipt.organization else { throw SetupFailure.recovery }
            if kind == "policies" {
                guard let app = receipt.application, resource.application_id == app else { throw SetupFailure.recovery }
            }
            do { _ = try await send("DELETE", path: "/iam/v1alpha1/\(kind)/\(resource.id)", session: session) }
            catch SetupFailure.rejected(404) { }
        }
        func removeKnown(_ id: String, kind: String) async throws {
            try uuid(id)
            do {
                let resource = try decode(Resource.self, await send("GET", path: "/iam/v1alpha1/\(kind)/\(id)", session: session))
                guard resource.id == id else { throw SetupFailure.recovery }
                try await remove(resource, kind: kind)
            } catch SetupFailure.rejected(404) { }
        }
        var clean = true
        do {
            if let id = receipt.policy { try await removeKnown(id, kind: "policies") }
            else {
                let policies = try decode(Policies.self, await send("GET", path: "/iam/v1alpha1/policies", session: session, query: [
                    .init(name: "organization_id", value: receipt.organization), .init(name: "policy_name", value: receipt.name), .init(name: "page_size", value: "100")]))
                guard policies.total_count == policies.policies.count else { throw SetupFailure.recovery }
                for policy in policies.policies { try await remove(policy, kind: "policies") }
            }
        } catch { clean = false }
        do {
            if let id = receipt.application { try await removeKnown(id, kind: "applications") }
            else {
                let applications = try decode(Applications.self, await send("GET", path: "/iam/v1alpha1/applications", session: session, query: [
                    .init(name: "organization_id", value: receipt.organization), .init(name: "name", value: receipt.name), .init(name: "page_size", value: "100")]))
                guard applications.total_count == applications.applications.count else { throw SetupFailure.recovery }
                for app in applications.applications { try await remove(app, kind: "applications") }
            }
        } catch { clean = false }
        // An unacknowledged POST could still complete after an empty listing. Never claim certainty.
        return clean && !receipt.uncertain
    }
}
