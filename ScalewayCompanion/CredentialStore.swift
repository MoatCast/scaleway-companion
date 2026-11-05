// SPDX-License-Identifier: MPL-2.0
import Foundation
import Security

protocol CredentialVault: Sendable {
    func load() async throws -> APICredentials?
    func save(_ credentials: APICredentials) async throws
    func delete() async throws
}

// Actor isolation keeps blocking Keychain operations off the UI actor.
actor KeychainCredentials: CredentialVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ScalewayCompanion.APIConnection",
         kSecAttrAccount as String: "default",
         kSecAttrSynchronizable as String: false]
    }
    func load() throws -> APICredentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let saved = try? JSONDecoder().decode(APICredentials.self, from: data) else { throw APIError.keychain }
        return try APICredentials(secret: saved.secret, organization: saved.organization, setupName: saved.setupName)
    }
    func save(_ credentials: APICredentials) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credentials),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw APIError.keychain }
        } else if status != errSecSuccess { throw APIError.keychain }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.keychain }
    }
}
