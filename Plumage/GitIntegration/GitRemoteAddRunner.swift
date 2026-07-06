import Foundation

nonisolated enum GitRemoteAddError: LocalizedError, Sendable, Equatable {
    case unsafeName(String)
    case unsafeURL(String)

    var errorDescription: String? {
        switch self {
        case .unsafeName(let name):
            return "Invalid remote name: '\(name)'"
        case .unsafeURL(let url):
            return "Invalid remote URL: '\(url)'"
        }
    }
}

nonisolated protocol GitRemoteAdding: Sendable {
    func addRemote(name: String, url: String, repoURL: URL) async throws
}

nonisolated struct GitRemoteAddRunner: GitRemoteAdding, GitCommandRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func addRemote(name: String, url: String, repoURL: URL) async throws {
        guard GitBranchName.isSafe(name) else { throw GitRemoteAddError.unsafeName(name) }
        // isSafe can't vet a URL. Beyond empty/leading-"-" (option injection), reject
        // remote-helper transports (ext::/fd::…) — they run a shell command on fetch.
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedURL.hasPrefix("-"), !Self.isRemoteHelper(trimmedURL) else {
            throw GitRemoteAddError.unsafeURL(url)
        }
        try await invokeGit(
            repoURL: repoURL,
            args: ["remote", "add", name, trimmedURL],
            command: "git remote add")
    }

    // Reject the remote-helper form "<transport>::<address>" (ext::, fd::). Scheme
    // URLs use "://" and scp-like a single ":", so only the helper form has "<name>::".
    static func isRemoteHelper(_ url: String) -> Bool {
        guard let colon = url.firstIndex(of: ":") else { return false }
        let next = url.index(after: colon)
        guard next < url.endIndex, url[next] == ":" else { return false }
        let transport = url[url.startIndex..<colon]
        guard !transport.isEmpty else { return false }
        return transport.allSatisfy { char in
            char.isLetter || char.isNumber || char == "+" || char == "-" || char == "."
        }
    }
}
