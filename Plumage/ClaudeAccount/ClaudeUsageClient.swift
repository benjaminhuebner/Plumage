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
    // requiring an organization-ID lookup. Discovered empirically on
    // 2026-05-20 (#00031, notes.md); the claude.ai/api/organizations/{id}/usage
    // endpoint the original spec referenced rejects this token with 403
    // account_session_invalid.
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
        do {
            token = try keychain.readToken()
        } catch ClaudeAccountAuthError.notLoggedIn {
            throw ClaudeUsageError.notLoggedIn
        } catch {
            throw ClaudeUsageError.transport(error.localizedDescription)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch {
            throw ClaudeUsageError.transport(error.localizedDescription)
        }
        switch response.statusCode {
        case 200..<300:
            do {
                return try ClaudeUsageResponse.decode(data: data)
            } catch {
                throw ClaudeUsageError.unparseable(error.localizedDescription)
            }
        case 401, 403:
            throw ClaudeUsageError.notLoggedIn
        default:
            throw ClaudeUsageError.serverError(response.statusCode)
        }
    }
}
