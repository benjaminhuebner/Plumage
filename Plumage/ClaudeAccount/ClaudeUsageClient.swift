import Foundation

nonisolated enum ClaudeUsageError: Error, Sendable, Equatable {
    case notLoggedIn
    case noOrganization
    case transport(String)
    case serverError(Int)
    case unparseable(String)
}

actor ClaudeUsageClient {
    static let claudeAIBaseURLString = "https://claude.ai"

    private let fetcher: any HTTPFetching
    private let keychain: any KeychainReading
    private let baseURL: URL
    private var cachedOrganizationID: String?

    init(
        fetcher: any HTTPFetching = ProductionHTTPFetcher(),
        keychain: any KeychainReading = ProductionKeychainReader(),
        baseURLString: String = ClaudeUsageClient.claudeAIBaseURLString
    ) {
        self.fetcher = fetcher
        self.keychain = keychain
        guard let url = URL(string: baseURLString) else {
            preconditionFailure("invalid claude.ai base URL literal: \(baseURLString)")
        }
        self.baseURL = url
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

        let orgID = try await resolveOrganizationID(token: token)
        let url = baseURL.appending(path: "/api/organizations/\(orgID)/usage")
        let data = try await get(url: url, token: token, mapDecode: ClaudeUsageError.unparseable)
        do {
            return try ClaudeUsageResponse.decode(data: data)
        } catch {
            throw ClaudeUsageError.unparseable(error.localizedDescription)
        }
    }

    func resetOrganizationCache() {
        cachedOrganizationID = nil
    }

    private func resolveOrganizationID(token: OAuthToken) async throws -> String {
        if let cached = cachedOrganizationID { return cached }
        let url = baseURL.appending(path: "/api/organizations")
        let data = try await get(url: url, token: token, mapDecode: ClaudeUsageError.unparseable)
        let orgs: [ClaudeOrganizationListing]
        do {
            orgs = try ClaudeOrganizationListing.decode(data: data)
        } catch {
            throw ClaudeUsageError.unparseable(error.localizedDescription)
        }
        guard let first = orgs.first else { throw ClaudeUsageError.noOrganization }
        cachedOrganizationID = first.id
        return first.id
    }

    private func get(
        url: URL,
        token: OAuthToken,
        mapDecode: (String) -> ClaudeUsageError
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The CLI's token is an OAuth access token. Bearer is the form
        // observed in the open-source Claude-Usage-Tracker reference and is
        // what claude.ai's web client uses; if Anthropic ever rotates the
        // call to a cookie-only path, swap to `Cookie: sessionKey=…`.
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch {
            throw ClaudeUsageError.transport(error.localizedDescription)
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403:
            throw ClaudeUsageError.notLoggedIn
        case 500...599:
            throw ClaudeUsageError.serverError(response.statusCode)
        default:
            throw ClaudeUsageError.serverError(response.statusCode)
        }
    }
}
