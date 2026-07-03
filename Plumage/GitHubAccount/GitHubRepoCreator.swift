import Foundation

nonisolated enum GitHubRepoCreatorError: LocalizedError, Sendable, Equatable {
    case unauthorized
    case insufficientScopes
    case rateLimited(String?)
    case nameAlreadyExists(String?)
    case serverError(Int)
    case transport(String)
    case unparseable(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "That token is invalid or expired."
        case .insufficientScopes:
            "That token cannot create repositories — it needs repository-creation access."
        case .rateLimited(let message):
            message ?? "GitHub's rate limit was hit. Wait a moment and try again."
        case .nameAlreadyExists(let message):
            message ?? "A repository with that name already exists on your account."
        case .serverError(let code):
            "GitHub returned an error (HTTP \(code))."
        case .transport:
            "Couldn't reach GitHub. Check your connection."
        case .unparseable:
            "GitHub returned an unexpected response."
        }
    }
}

nonisolated struct CreatedGitHubRepo: Sendable, Equatable {
    let cloneURL: URL
    let fullName: String?
}

nonisolated struct GitHubRepoCreator: Sendable {
    static let reposEndpointString = "https://api.github.com/user/repos"
    static let reposEndpoint: URL = {
        guard let url = URL(string: reposEndpointString) else {
            preconditionFailure("invalid GitHub repos endpoint literal")
        }
        return url
    }()

    let fetcher: any HTTPFetching
    let endpoint: URL

    init(
        fetcher: any HTTPFetching = ProductionHTTPFetcher(),
        endpoint: URL = GitHubRepoCreator.reposEndpoint
    ) {
        self.fetcher = fetcher
        self.endpoint = endpoint
    }

    func createRepo(name: String, isPrivate: Bool, token: String) async throws -> CreatedGitHubRepo {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(RequestBody(name: name, isPrivate: isPrivate))
        } catch {
            throw GitHubRepoCreatorError.unparseable(error.localizedDescription)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GitHubRepoCreatorError.transport(error.localizedDescription)
        }

        switch response.statusCode {
        case 200..<300: break
        case 401: throw GitHubRepoCreatorError.unauthorized
        case 403 where Self.isRateLimited(response, data):
            throw GitHubRepoCreatorError.rateLimited(Self.parseMessage(data))
        case 403, 404: throw GitHubRepoCreatorError.insufficientScopes
        case 422: throw GitHubRepoCreatorError.nameAlreadyExists(Self.parseMessage(data))
        default: throw GitHubRepoCreatorError.serverError(response.statusCode)
        }

        let body: RepoBody
        do {
            body = try JSONDecoder().decode(RepoBody.self, from: data)
        } catch {
            throw GitHubRepoCreatorError.unparseable(error.localizedDescription)
        }
        guard let cloneURL = body.cloneURL else {
            throw GitHubRepoCreatorError.unparseable("response has no clone_url")
        }
        return CreatedGitHubRepo(cloneURL: cloneURL, fullName: body.fullName)
    }

    // GitHub puts the useful 422 text in errors[].message ("name already exists
    // on this account"); the top-level message is the generic envelope.
    static func parseMessage(_ data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        if let specific = body.errors?.compactMap(\.message).first(where: { !$0.isEmpty }) {
            return specific
        }
        return body.message
    }

    // GitHub overloads 403 for both missing scopes and rate/abuse limits; only the
    // latter carry Retry-After / X-RateLimit-Remaining: 0 or say "rate limit".
    static func isRateLimited(_ response: HTTPURLResponse, _ data: Data) -> Bool {
        if response.value(forHTTPHeaderField: "Retry-After") != nil { return true }
        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" { return true }
        return String(decoding: data, as: UTF8.self).lowercased().contains("rate limit")
    }

    private struct RequestBody: Encodable {
        let name: String
        let isPrivate: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case isPrivate = "private"
        }
    }

    private struct RepoBody: Decodable {
        let cloneURL: URL?
        let fullName: String?

        enum CodingKeys: String, CodingKey {
            case cloneURL = "clone_url"
            case fullName = "full_name"
        }
    }

    private struct ErrorBody: Decodable {
        let message: String?
        let errors: [Item]?

        struct Item: Decodable {
            let message: String?
        }
    }
}
