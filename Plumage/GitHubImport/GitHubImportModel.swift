import Foundation
import Observation

@MainActor
@Observable
final class GitHubImportModel {
    enum State: Sendable, Equatable {
        case idle
        case loading
        case loaded([GitHubIssue])
        case empty
        case unavailable(reason: String, connectAccount: Bool)
        case rateLimited(String?)
        case failed(String)

        var hasIssues: Bool {
            switch self {
            case .loaded, .empty: true
            default: false
            }
        }
    }

    let projectURL: URL

    private(set) var state: State = .idle
    private(set) var repoLabel: String?
    private(set) var isRefreshing = false
    private(set) var justAdopted: Set<Int> = []
    private(set) var adoptError: String?

    private let boundAccountID: String?
    private let remoteRunner: GitRemoteURLRunner
    private let accountStore: GitHubAccountStore
    private let credentialStore: any GitHubCredentialStoring
    private let client: GitHubIssuesClient
    private let allocator: NextIssueAllocator
    private let openInEditor: @MainActor (String) -> Void

    init(
        projectURL: URL,
        boundAccountID: String?,
        remoteRunner: GitRemoteURLRunner = GitRemoteURLRunner(runner: ProductionGitProcessRunner()),
        accountStore: GitHubAccountStore = GitHubAccountStore(),
        credentialStore: any GitHubCredentialStoring = ProductionGitHubCredentialStore(),
        client: GitHubIssuesClient = GitHubIssuesClient(),
        allocator: NextIssueAllocator? = nil,
        openInEditor: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.projectURL = projectURL
        self.boundAccountID = boundAccountID
        self.remoteRunner = remoteRunner
        self.accountStore = accountStore
        self.credentialStore = credentialStore
        self.client = client
        self.allocator = allocator ?? NextIssueAllocator(projectURL: projectURL)
        self.openInEditor = openInEditor
    }

    var openCount: Int {
        if case .loaded(let issues) = state { return issues.count }
        return 0
    }

    #if DEBUG
    func _setStateForTesting(_ state: State, justAdopted: Set<Int> = []) {
        self.state = state
        self.justAdopted = justAdopted
    }
    #endif

    func load() async {
        state = .loading
        await fetch(keepLastOnTransportError: false)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(keepLastOnTransportError: true)
    }

    func adopt(_ issue: GitHubIssue) {
        let number = issue.number
        guard !justAdopted.contains(number) else { return }
        justAdopted.insert(number)
        adoptError = nil
        do {
            let folderName = try GitHubIssueAdopter.allocate(
                allocator: allocator, title: issue.title, labels: issue.labels,
                body: issue.body ?? "", number: number)
            openInEditor(folderName)
        } catch {
            justAdopted.remove(number)
            adoptError = (error as? LocalizedError)?.errorDescription ?? "Couldn't create the issue."
        }
    }

    private func fetch(keepLastOnTransportError: Bool) async {
        guard let target = await resolve() else { return }
        do {
            let issues = try await client.listOpenIssues(
                owner: target.owner, repo: target.repo, token: target.token)
            state = issues.isEmpty ? .empty : .loaded(issues)
        } catch is CancellationError {
        } catch let error as GitHubIssuesClientError {
            apply(error, keepLastOnTransportError: keepLastOnTransportError)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func apply(_ error: GitHubIssuesClientError, keepLastOnTransportError: Bool) {
        switch error {
        case .rateLimited(let message):
            state = .rateLimited(message)
        case .transport where keepLastOnTransportError && state.hasIssues:
            break
        default:
            state = .failed(error.errorDescription ?? "GitHub request failed.")
        }
    }

    private struct ResolvedTarget: Sendable {
        let owner: String
        let repo: String
        let token: String
    }

    private func resolve() async -> ResolvedTarget? {
        guard let remote = await remoteRunner.originRemote(for: projectURL),
            remote.host == GitHubAccount.defaultHost, let repo = remote.repo
        else {
            state = .unavailable(
                reason: "This project has no github.com origin remote.", connectAccount: false)
            return nil
        }
        repoLabel = "\(remote.owner)/\(repo)"

        let accountStore = accountStore
        let credentialStore = credentialStore
        let boundAccountID = boundAccountID
        let owner = remote.owner
        let token = await Task.detached(priority: .userInitiated) { () -> String? in
            let accounts = accountStore.load()
            guard
                let account = GitHubAccountResolver.resolve(
                    host: GitHubAccount.defaultHost, owner: owner,
                    accounts: accounts, boundAccountID: boundAccountID),
                let token = try? credentialStore.readToken(login: account.login, host: account.host),
                !token.isEmpty
            else { return nil }
            return token
        }.value

        guard let token else {
            state = .unavailable(
                reason: "Connect a GitHub account in Settings → Accounts to import issues.",
                connectAccount: true)
            return nil
        }
        return ResolvedTarget(owner: owner, repo: repo, token: token)
    }
}

nonisolated enum GitHubIssueAdopter {
    static func allocate(
        allocator: NextIssueAllocator, title: String, labels: [String], body: String, number: Int
    ) throws -> String {
        let base = NextIssueAllocator.slugify(title)
        let slug = base.isEmpty ? "gh\(number)" : base
        let url = try allocateOnce(
            allocator, slug: slug, title: title, labels: labels, body: body, number: number)
        return url.deletingLastPathComponent().lastPathComponent
    }

    private static func allocateOnce(
        _ allocator: NextIssueAllocator, slug: String, title: String, labels: [String],
        body: String, number: Int
    ) throws -> URL {
        do {
            return try allocator.allocate(
                slug: slug, title: title, type: .feature, labels: labels, prompt: body, github: number)
        } catch NextIssueAllocatorError.slugCollision {
            return try allocator.allocate(
                slug: "\(slug)-gh\(number)", title: title, type: .feature, labels: labels,
                prompt: body, github: number)
        }
    }
}
