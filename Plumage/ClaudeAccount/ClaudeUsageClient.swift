import Foundation

nonisolated enum ClaudeUsageError: Error, Sendable, Equatable {
    case notLoggedIn
    case transport(String)
    case serverError(Int)
    case unparseable(String)
}

actor ClaudeUsageClient {
    // The CLI OAuth token is accepted at api.anthropic.com with a Bearer
    // header plus the `anthropic-version` API-version header. The
    // `/api/oauth/usage` endpoint returns per-window utilization without
    // requiring an organization-ID lookup. Discovered empirically; the
    // claude.ai/api/organizations/{id}/usage endpoint the original spec
    // referenced rejects this token with 403 account_session_invalid.
    static let usageEndpointString = "https://api.anthropic.com/api/oauth/usage"
    static let usageEndpoint: URL = {
        guard let url = URL(string: usageEndpointString) else {
            preconditionFailure("invalid usage endpoint literal")
        }
        return url
    }()

    private let fetcher: any HTTPFetching
    private let keychain: any KeychainReading
    private let endpoint: URL

    // Caching avoids a `security` subprocess spawn on every poll. In-memory
    // only: persisting a copy would be "own credential handling".
    private var cachedToken: OAuthToken?

    init(
        fetcher: any HTTPFetching = ProductionHTTPFetcher(),
        keychain: any KeychainReading = ProductionKeychainReader(),
        endpoint: URL = ClaudeUsageClient.usageEndpoint
    ) {
        self.fetcher = fetcher
        self.keychain = keychain
        self.endpoint = endpoint
    }

    func fetchUsage() async throws -> ClaudeUsageResponse {
        let token: OAuthToken
        if let cachedToken, !Self.isExpired(cachedToken) {
            token = cachedToken
        } else {
            // An expired cached token would guarantee a 401 and a one-poll
            // .notLoggedIn flicker per rotation — treat it as a cache miss so
            // the CLI's refreshed token is read instead.
            token = try await readToken()
        }

        do {
            return try await requestUsage(token: token)
        } catch ClaudeUsageError.notLoggedIn {
            // The token was rejected (rotated, revoked, or expired). Drop it so
            // the next poll reads a fresh one — the CLI has by then written the
            // refreshed token.
            cachedToken = nil
            throw ClaudeUsageError.notLoggedIn
        }
    }

    private nonisolated static func isExpired(_ token: OAuthToken) -> Bool {
        guard let expiresAt = token.expiresAt else { return false }
        return expiresAt <= .now
    }

    private func readToken() async throws -> OAuthToken {
        do {
            let token = try await keychain.readToken()
            cachedToken = token
            return token
        } catch ClaudeAccountAuthError.notLoggedIn {
            throw ClaudeUsageError.notLoggedIn
        } catch {
            throw ClaudeUsageError.transport(error.localizedDescription)
        }
    }

    private func requestUsage(token: OAuthToken) async throws -> ClaudeUsageResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let data = try await fetcher.successData(
            for: request,
            transportError: { ClaudeUsageError.transport($0.localizedDescription) },
            statusError: { code in
                code == 401 || code == 403
                    ? ClaudeUsageError.notLoggedIn
                    : ClaudeUsageError.serverError(code)
            })
        do {
            return try ClaudeUsageResponse.decode(data: data)
        } catch {
            throw ClaudeUsageError.unparseable(error.localizedDescription)
        }
    }
}
