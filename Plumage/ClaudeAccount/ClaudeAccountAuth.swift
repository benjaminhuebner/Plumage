import Foundation
import Security
import os

nonisolated struct OAuthToken: Sendable, Equatable {
    let value: String
    let expiresAt: Date?
}

nonisolated enum ClaudeAccountAuthError: Error, Sendable, Equatable {
    case notLoggedIn
    case readFailed(String)
    case malformedItem(String)
}

nonisolated protocol KeychainReading: Sendable {
    func readToken() async throws -> OAuthToken
}

nonisolated enum ClaudeKeychain {
    // Empirically observed service name used by the `claude` CLI when it
    // stores its OAuth token in the macOS Keychain. If the CLI ever rotates
    // this, the reader returns `.notLoggedIn` — no crash, no stale data.
    static let serviceName = "Claude Code-credentials"
    static let itemNotFoundExit: Int32 = 44
}

nonisolated struct KeychainServiceCandidate: Sendable, Equatable {
    let service: String
    let modifiedAt: Date?
}

nonisolated protocol KeychainServiceDiscovering: Sendable {
    func candidateServices(prefix: String) -> [KeychainServiceCandidate]
}

nonisolated struct ProductionKeychainServiceDiscovery: KeychainServiceDiscovering {
    func candidateServices(prefix: String) -> [KeychainServiceCandidate] {
        // Attribute-only enumeration: the ACL guards the secret, not the
        // attributes, so this never prompts — unlike any kSecReturnData read.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess, let attributes = items as? [[String: Any]] else {
            return []
        }
        return attributes.compactMap { item in
            guard let service = item[kSecAttrService as String] as? String,
                service.hasPrefix(prefix)
            else { return nil }
            return KeychainServiceCandidate(
                service: service,
                modifiedAt: item[kSecAttrModificationDate as String] as? Date)
        }
    }
}

nonisolated struct ProductionKeychainReader: KeychainReading {
    let serviceName: String
    private let runner: any SecurityToolRunning
    private let discovery: any KeychainServiceDiscovering
    // Copies share the lock allocation — intended: one reader per client,
    // and the resolved name must survive across readToken() calls.
    private let resolvedService = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(
        serviceName: String = ClaudeKeychain.serviceName,
        runner: any SecurityToolRunning = ProductionSecurityToolRunner(),
        discovery: any KeychainServiceDiscovering = ProductionKeychainServiceDiscovery()
    ) {
        self.serviceName = serviceName
        self.runner = runner
        self.discovery = discovery
    }

    func readToken() async throws -> OAuthToken {
        if let cached = resolvedService.withLock({ $0 }) {
            do {
                return try await read(service: cached)
            } catch ClaudeAccountAuthError.notLoggedIn {
                resolvedService.withLock { $0 = nil }
            }
        }
        do {
            let token = try await read(service: serviceName)
            resolvedService.withLock { $0 = serviceName }
            return token
        } catch ClaudeAccountAuthError.notLoggedIn {
            return try await readHashedFallback()
        }
    }

    // Claude Code may store under `Claude Code-credentials-<hash>` instead of
    // the legacy name; discover it once and pin it for this reader's lifetime.
    private func readHashedFallback() async throws -> OAuthToken {
        let candidates = discovery.candidateServices(prefix: serviceName + "-")
        let best = candidates.max { lhs, rhs in
            (lhs.modifiedAt ?? .distantPast) < (rhs.modifiedAt ?? .distantPast)
        }
        guard let best else {
            throw ClaudeAccountAuthError.notLoggedIn
        }
        let token = try await read(service: best.service)
        resolvedService.withLock { $0 = best.service }
        return token
    }

    private func read(service: String) async throws -> OAuthToken {
        // Read via `security`, not SecItemCopyMatching: the CLI rewrites its
        // item on every OAuth refresh, resetting the ACL, so an app-direct
        // read re-prompts forever — Apple's tool stays permitted persistently.
        let result: SecurityToolResult
        do {
            result = try await runner.run(args: [
                "find-generic-password", "-s", service, "-a", NSUserName(), "-w",
            ])
        } catch let error as SecurityToolError {
            switch error {
            case .timedOut:
                throw ClaudeAccountAuthError.readFailed("security timed out")
            case .spawnFailed(let description):
                throw ClaudeAccountAuthError.readFailed(
                    "failed to launch security: \(description)")
            }
        }
        if result.exitCode == ClaudeKeychain.itemNotFoundExit {
            throw ClaudeAccountAuthError.notLoggedIn
        }
        guard result.exitCode == 0 else {
            throw ClaudeAccountAuthError.readFailed(
                "security exited with code \(result.exitCode)")
        }
        let payload = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            throw ClaudeAccountAuthError.notLoggedIn
        }
        return try Self.decode(data: Data(payload.utf8))
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
