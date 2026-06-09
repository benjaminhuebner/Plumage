import Foundation

nonisolated struct RepoState: Sendable, Equatable, Hashable {
    let isGitRepo: Bool
    let branchName: String?
    let isDetached: Bool
    let detachedSHA: String?

    static let notARepo = RepoState(
        isGitRepo: false, branchName: nil, isDetached: false, detachedSHA: nil)

    init(isGitRepo: Bool, branchName: String?, isDetached: Bool, detachedSHA: String?) {
        self.isGitRepo = isGitRepo
        self.branchName = branchName
        self.isDetached = isDetached
        self.detachedSHA = detachedSHA
    }

    static func branch(_ name: String) -> RepoState {
        RepoState(isGitRepo: true, branchName: name, isDetached: false, detachedSHA: nil)
    }

    static func detached(sha: String) -> RepoState {
        RepoState(isGitRepo: true, branchName: nil, isDetached: true, detachedSHA: sha)
    }

    var displayLabel: String? {
        if !isGitRepo { return nil }
        if let branchName { return branchName }
        if let detachedSHA { return "(detached) \(detachedSHA)" }
        return nil
    }
}

// Synchronous reader for `.git/HEAD`. Cheap enough to run on every debounced
// FSEvent — touching the file system but not spawning git. Format:
//   `ref: refs/heads/<branch>\n` — branch state
//   `<40 or so hex chars>\n`     — detached HEAD
nonisolated struct RepoStateReader: Sendable {
    let fileManager: @Sendable (URL) -> Bool
    let readFile: @Sendable (URL) -> String?

    init(
        fileManager: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path)
        },
        readFile: @escaping @Sendable (URL) -> String? = { url in
            try? String(contentsOf: url, encoding: .utf8)
        }
    ) {
        self.fileManager = fileManager
        self.readFile = readFile
    }

    func read(repoURL: URL) -> RepoState {
        let gitEntry = repoURL.appendingPathComponent(".git")
        guard fileManager(gitEntry) else { return .notARepo }
        let headURL = headFileURL(repoURL: repoURL, gitEntry: gitEntry)
        guard let raw = readFile(headURL) else { return .notARepo }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            let name = String(trimmed.dropFirst("ref: refs/heads/".count))
            return .branch(name)
        }
        if trimmed.hasPrefix("ref: ") {
            // Symbolic-ref pointing at something other than refs/heads/ —
            // treat as detached for UI purposes; the user sees the bare ref.
            let name = String(trimmed.dropFirst("ref: ".count))
            return .branch(name)
        }
        // Bare SHA — detached. Truncate to short form for UI display.
        let short = String(trimmed.prefix(7))
        return .detached(sha: short)
    }

    // Worktrees and submodules: `.git` is a FILE containing
    // "gitdir: <path>" — reading the entry as a string fails for the
    // regular directory layout (→ fall through to .git/HEAD).
    private func headFileURL(repoURL: URL, gitEntry: URL) -> URL {
        if let raw = readFile(gitEntry),
            raw.hasPrefix("gitdir: ")
        {
            let target = raw.dropFirst("gitdir: ".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let dir =
                target.hasPrefix("/")
                ? URL(filePath: target, directoryHint: .isDirectory)
                : repoURL.appendingPathComponent(target, isDirectory: true).standardizedFileURL
            return dir.appendingPathComponent("HEAD")
        }
        return gitEntry.appendingPathComponent("HEAD")
    }
}
