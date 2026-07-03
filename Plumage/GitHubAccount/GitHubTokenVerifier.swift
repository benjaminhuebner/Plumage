import Foundation

nonisolated enum GitHubTokenVerifierError: LocalizedError, Sendable, Equatable {
    case unauthorized
    case serverError(Int)
    case transport(String)
    case unparseable(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "That token is invalid or expired."
        case .serverError(let code): "GitHub returned an error (HTTP \(code))."
        case .transport: "Couldn't reach GitHub. Check your connection."
        case .unparseable: "GitHub returned an unexpected response."
        }
    }
}

nonisolated struct VerifiedGitHubUser: Sendable, Equatable {
    let login: String
    let name: String?
    let avatarURL: URL?
    // Empty for fine-grained PATs — GitHub omits the x-oauth-scopes header for them.
    let scopes: [String]
}

nonisolated struct GitHubTokenVerifier: Sendable {
    static let userEndpointString = "https://api.github.com/user"
    static let userEndpoint: URL = {
        guard let url = URL(string: userEndpointString) else {
            preconditionFailure("invalid GitHub user endpoint literal")
        }
        return url
    }()

    let fetcher: any HTTPFetching
    let endpoint: URL

    init(
        fetcher: any HTTPFetching = ProductionHTTPFetcher(),
        endpoint: URL = GitHubTokenVerifier.userEndpoint
    ) {
        self.fetcher = fetcher
        self.endpoint = endpoint
    }

    func verify(token: String) async throws -> VerifiedGitHubUser {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GitHubTokenVerifierError.transport(error.localizedDescription)
        }

        switch response.statusCode {
        case 200: break
        case 401: throw GitHubTokenVerifierError.unauthorized
        default: throw GitHubTokenVerifierError.serverError(response.statusCode)
        }

        let user: UserBody
        do {
            user = try JSONDecoder().decode(UserBody.self, from: data)
        } catch {
            throw GitHubTokenVerifierError.unparseable(error.localizedDescription)
        }
        return VerifiedGitHubUser(
            login: user.login,
            name: user.name,
            avatarURL: user.avatarURL,
            scopes: Self.parseScopes(response.value(forHTTPHeaderField: "x-oauth-scopes")))
    }

    static func parseScopes(_ header: String?) -> [String] {
        guard let header else { return [] }
        return
            header
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private struct UserBody: Decodable {
        let login: String
        let name: String?
        let avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case login, name
            case avatarURL = "avatar_url"
        }
    }
}
