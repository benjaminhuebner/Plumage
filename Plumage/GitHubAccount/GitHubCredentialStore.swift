import Foundation
import Security

nonisolated enum GitHubCredentialStoreError: Error, Sendable, Equatable {
    case tokenNotUTF8
    case unexpectedStatus(OSStatus)
}

nonisolated protocol GitHubCredentialStoring: Sendable {
    func saveToken(_ token: String, login: String, host: String) throws
    func readToken(login: String, host: String) throws -> String?
    func deleteToken(login: String, host: String) throws
}

nonisolated struct ProductionGitHubCredentialStore: GitHubCredentialStoring {
    static let defaultService = "Plumage GitHub"

    let service: String

    init(service: String = ProductionGitHubCredentialStore.defaultService) {
        self.service = service
    }

    func saveToken(_ token: String, login: String, host: String) throws {
        guard let data = token.data(using: .utf8) else { throw GitHubCredentialStoreError.tokenNotUTF8 }
        // Update-then-add preserves item metadata and avoids the delete/add race.
        var status = SecItemUpdate(
            baseQuery(login: login, host: host) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery(login: login, host: host)
            addQuery[kSecValueData as String] = data
            // Device-bound: a push token has no reason to ride into an encrypted
            // backup or migrate to another Mac. AfterFirstUnlock keeps it readable
            // for a background-triggered push without a prompt.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw GitHubCredentialStoreError.unexpectedStatus(status) }
    }

    func readToken(login: String, host: String) throws -> String? {
        var query = baseQuery(login: login, host: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GitHubCredentialStoreError.unexpectedStatus(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw GitHubCredentialStoreError.unexpectedStatus(errSecDecode)
        }
        return token
    }

    func deleteToken(login: String, host: String) throws {
        let status = SecItemDelete(baseQuery(login: login, host: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubCredentialStoreError.unexpectedStatus(status)
        }
    }

    // Data-protection keychain (the modern, iOS-aligned path per TN3137): needs
    // the keychain-access-group entitlement, provisioned via Keychain Sharing.
    // Plumage owns the item, so its own reads aren't prompted.
    private func baseQuery(login: String, host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: GitHubAccount.identifier(login: login, host: host),
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
