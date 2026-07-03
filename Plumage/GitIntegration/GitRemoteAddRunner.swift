import Foundation

nonisolated enum GitRemoteAddError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case unsafeName(String)
    case unsafeURL(String)
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .unsafeName(let name):
            return "Invalid remote name: '\(name)'"
        case .unsafeURL(let url):
            return "Invalid remote URL: '\(url)'"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(_, let stderr):
            return "git remote add failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

nonisolated protocol GitRemoteAdding: Sendable {
    func addRemote(name: String, url: String, repoURL: URL) async throws
}

nonisolated struct GitRemoteAddRunner: GitRemoteAdding {
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
        guard let binary = resolveBinary() else { throw GitRemoteAddError.gitNotFound }
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "remote", "add", name, trimmedURL],
                cwd: nil)
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }
        guard result.exitCode == 0 else {
            throw GitRemoteAddError.nonZeroExit(
                code: result.exitCode, stderr: String(decoding: result.stderr, as: UTF8.self))
        }
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

    static func map(_ error: GitProcessRunnerError) -> GitRemoteAddError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
