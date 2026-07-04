import Foundation

nonisolated enum GitHubIssuesClientError: LocalizedError, Sendable, Equatable {
    case unauthorized
    case notFound
    case rateLimited(String?)
    case serverError(Int)
    case transport(String)
    case unparseable(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "That token is invalid or expired."
        case .notFound:
            "Repository not found, or the token can't read its issues. Connect a GitHub account with issue read access."
        case .rateLimited(let message):
            message ?? "GitHub's rate limit was hit. Wait a moment and try again."
        case .serverError(let code):
            "GitHub returned an error (HTTP \(code))."
        case .transport:
            "Couldn't reach GitHub. Check your connection."
        case .unparseable:
            "GitHub returned an unexpected response."
        }
    }
}

nonisolated struct GitHubIssue: Sendable, Identifiable, Equatable {
    var id: Int { number }
    let number: Int
    let title: String
    let body: String?
    let htmlURL: URL
    let labels: [String]
    let updatedAt: Date
    let authorLogin: String?
}

nonisolated struct GitHubIssuesClient: Sendable {
    static let apiBaseString = "https://api.github.com"
    static let apiBase: URL = {
        guard let url = URL(string: apiBaseString) else {
            preconditionFailure("invalid GitHub API base literal")
        }
        return url
    }()

    // Serial pagination backstop: the loop follows rel="next" verbatim, so a
    // misbehaving Link header can't spin forever. Well above any realistic
    // open-issue count (100 per page).
    private static let maxPages = 10
    private static let maxRedirects = 5

    let fetcher: any HTTPFetching
    let apiBase: URL

    init(
        fetcher: any HTTPFetching = ProductionHTTPFetcher(),
        apiBase: URL = GitHubIssuesClient.apiBase
    ) {
        self.fetcher = fetcher
        self.apiBase = apiBase
    }

    func listOpenIssues(owner: String, repo: String, token: String) async throws -> [GitHubIssue] {
        guard var url = Self.issuesURL(owner: owner, repo: repo, base: apiBase) else {
            throw GitHubIssuesClientError.unparseable("could not build the issues URL")
        }
        var collected: [GitHubIssue] = []
        var page = 0
        while page < Self.maxPages {
            page += 1
            let (data, response) = try await fetchFollowingRedirects(url: url, token: token)
            try Self.checkStatus(response, data)
            let raw = try Self.decodeIssues(data)
            collected.append(contentsOf: raw.compactMap { $0.asIssue() })
            guard let next = Self.nextPageURL(from: response.value(forHTTPHeaderField: "Link")) else {
                break
            }
            url = next
        }
        return collected
    }

    private func fetchFollowingRedirects(
        url: URL, token: String
    ) async throws -> (Data, HTTPURLResponse) {
        var target = url
        for _ in 0...Self.maxRedirects {
            let (data, response) = try await send(url: target, token: token)
            // URLSession auto-follows in production; this covers a fetcher (or a
            // renamed/transferred repo, 301) that surfaces the redirect raw.
            guard [301, 302, 307, 308].contains(response.statusCode),
                let location = response.value(forHTTPHeaderField: "Location"),
                let next = URL(string: location, relativeTo: target)?.absoluteURL
            else {
                return (data, response)
            }
            target = next
        }
        throw GitHubIssuesClientError.transport("too many redirects")
    }

    private func send(url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            return try await fetcher.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GitHubIssuesClientError.transport(error.localizedDescription)
        }
    }

    private static func checkStatus(_ response: HTTPURLResponse, _ data: Data) throws {
        switch response.statusCode {
        case 200..<300: break
        case 401: throw GitHubIssuesClientError.unauthorized
        case 403 where GitHubRepoCreator.isRateLimited(response, data), 429:
            throw GitHubIssuesClientError.rateLimited(GitHubRepoCreator.parseMessage(data))
        case 404: throw GitHubIssuesClientError.notFound
        default: throw GitHubIssuesClientError.serverError(response.statusCode)
        }
    }

    private static func decodeIssues(_ data: Data) throws -> [RawIssue] {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([RawIssue].self, from: data)
        } catch {
            throw GitHubIssuesClientError.unparseable(error.localizedDescription)
        }
    }

    static func issuesURL(owner: String, repo: String, base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/repos/\(owner)/\(repo)/issues"
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        return components.url
    }

    // Link: <https://api.github.com/…&page=2>; rel="next", <…>; rel="last"
    static func nextPageURL(from linkHeader: String?) -> URL? {
        guard let linkHeader else { return nil }
        for part in linkHeader.split(separator: ",") {
            let segments = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard segments.count >= 2, let urlSegment = segments.first,
                segments.dropFirst().contains(where: { $0 == "rel=\"next\"" }),
                urlSegment.hasPrefix("<"), urlSegment.hasSuffix(">")
            else { continue }
            return URL(string: String(urlSegment.dropFirst().dropLast()))
        }
        return nil
    }

    private struct RawIssue: Decodable {
        let number: Int
        let title: String
        let body: String?
        let htmlURL: URL?
        let labels: [RawLabel]?
        let updatedAt: Date?
        let user: RawUser?
        let pullRequest: PullRequestMarker?

        enum CodingKeys: String, CodingKey {
            case number, title, body, labels, user
            case htmlURL = "html_url"
            case updatedAt = "updated_at"
            case pullRequest = "pull_request"
        }

        struct RawLabel: Decodable { let name: String? }
        struct RawUser: Decodable { let login: String? }
        // Empty: presence of the key alone marks a PR in the issues feed.
        struct PullRequestMarker: Decodable {}

        func asIssue() -> GitHubIssue? {
            guard pullRequest == nil, let htmlURL else { return nil }
            return GitHubIssue(
                number: number,
                title: title,
                body: body,
                htmlURL: htmlURL,
                labels: (labels ?? []).compactMap(\.name),
                updatedAt: updatedAt ?? Date(timeIntervalSince1970: 0),
                authorLogin: user?.login)
        }
    }
}
