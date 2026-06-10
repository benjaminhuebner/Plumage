import Foundation
import Security

nonisolated struct OAuthToken: Sendable, Equatable {
    let value: String
    let expiresAt: Date?
}

nonisolated enum ClaudeAccountAuthError: Error, Sendable, Equatable {
    case notLoggedIn
    case keychainFailure(OSStatus)
    case malformedItem(String)
}

nonisolated protocol KeychainReading: Sendable {
    func readToken() throws -> OAuthToken
}

nonisolated enum ClaudeKeychain {
    // Empirically observed service name used by the `claude` CLI when it
    // stores its OAuth token in the macOS Keychain. Same value the
    // `Claude-Usage-Tracker` MIT project reads from. If the CLI ever rotates
    // this, `ProductionKeychainReader` returns `.notLoggedIn` and the user
    // sees the LoggedOut path — no crash, no stale data.
    static let serviceName = "Claude Code-credentials"
}

nonisolated struct ProductionKeychainReader: KeychainReading {
    let serviceName: String

    init(serviceName: String = ClaudeKeychain.serviceName) {
        self.serviceName = serviceName
    }

    func readToken() throws -> OAuthToken {
        // Requesting both kSecReturnData AND kSecReturnAttributes triggered
        // errSecItemNotFound for items written by another signed app (the
        // claude CLI) even though the item is visible to an existence-check.
        // Data-only avoids that path; we don't need the attributes for the
        // OAuth-only payload.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            throw ClaudeAccountAuthError.notLoggedIn
        }
        guard status == errSecSuccess else {
            throw ClaudeAccountAuthError.keychainFailure(status)
        }
        guard let data = item as? Data else {
            throw ClaudeAccountAuthError.malformedItem("missing v_Data")
        }
        return try Self.decode(data: data)
    }

    static func decode(data: Data) throws -> OAuthToken {
        // The CLI stores either a JSON envelope (multiple observed shapes:
        // `{ "claudeAiOauth": { "accessToken": "...", "expiresAt": <ms> } }`,
        // `{ "accessToken": "..." }`, or top-level `{ "access_token": "..." }`)
        // or, on older builds, the raw access-token string. Probe in order.
        if let token = decodeEnvelope(data: data) {
            return token
        }
        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty, !raw.hasPrefix("{")
        {
            return OAuthToken(value: raw, expiresAt: nil)
        }
        throw ClaudeAccountAuthError.malformedItem("could not decode keychain payload")
    }

    private static func decodeEnvelope(data: Data) -> OAuthToken? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else { return nil }

        let inner: [String: Any]
        if let nested = dict["claudeAiOauth"] as? [String: Any] {
            inner = nested
        } else {
            inner = dict
        }

        let value =
            (inner["accessToken"] as? String)
            ?? (inner["access_token"] as? String)
            ?? (inner["token"] as? String)
        guard let accessToken = value, !accessToken.isEmpty else { return nil }

        let expires: Date?
        if let millis = inner["expiresAt"] as? Double {
            expires = Date(timeIntervalSince1970: millis / 1000)
        } else if let millis = inner["expires_at"] as? Double {
            expires = Date(timeIntervalSince1970: millis / 1000)
        } else if let seconds = inner["expires_in"] as? Double {
            expires = Date(timeIntervalSinceNow: seconds)
        } else {
            expires = nil
        }
        return OAuthToken(value: accessToken, expiresAt: expires)
    }
}
