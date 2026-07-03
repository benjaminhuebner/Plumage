import Foundation

nonisolated struct GitRemoteInfo: Sendable, Equatable {
    let host: String
    let owner: String
}

nonisolated struct GitRemoteURLRunner: Sendable {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning,
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func originRemote(for repoURL: URL) async -> GitRemoteInfo? {
        await remoteInfo(for: repoURL, remote: "origin")
    }

    // Host/owner for an arbitrary remote, so credential resolution can follow the
    // remote the user picked in the push sheet — not just origin.
    func remoteInfo(for repoURL: URL, remote: String) async -> GitRemoteInfo? {
        guard let binary = resolveBinary(), GitBranchName.isSafe(remote) else { return nil }
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "remote", "get-url", remote],
                cwd: nil)
        } catch {
            return nil
        }
        guard result.exitCode == 0 else { return nil }
        let raw = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.parse(remoteURL: raw)
    }

    static func parse(remoteURL: String) -> GitRemoteInfo? {
        guard !remoteURL.isEmpty else { return nil }
        // scp-like form (git@host:owner/repo.git) carries no scheme, so URLComponents
        // can't parse it — split on the first '@' and ':' by hand.
        if !remoteURL.contains("://"),
            let at = remoteURL.firstIndex(of: "@"),
            let colon = remoteURL[remoteURL.index(after: at)...].firstIndex(of: ":")
        {
            let host = String(remoteURL[remoteURL.index(after: at)..<colon])
            let path = String(remoteURL[remoteURL.index(after: colon)...])
            guard !host.isEmpty, let owner = firstComponent(path) else { return nil }
            return GitRemoteInfo(host: host.lowercased(), owner: owner)
        }
        guard let components = URLComponents(string: remoteURL),
            let host = components.host, !host.isEmpty,
            let owner = firstComponent(components.path)
        else { return nil }
        return GitRemoteInfo(host: host.lowercased(), owner: owner)
    }

    private static func firstComponent(_ path: String) -> String? {
        path.split(separator: "/").map(String.init).first
    }
}
