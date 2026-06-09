import Foundation

nonisolated enum GitMergeMode: String, Sendable, Equatable {
    case squash
    case fastForward
}

nonisolated enum GitMergeError: Error, Sendable, Equatable {
    case gitNotFound
    case workingTreeDirty(files: [String])
    case branchNotFound(name: String)
    case notFastForward(defaultBranch: String, issueBranch: String)
    case checkoutFailed(stderr: String)
    case mergeFailed(mode: GitMergeMode, stderr: String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .workingTreeDirty(let files):
            let head = files.prefix(5).joined(separator: ", ")
            let suffix = files.count > 5 ? " …and \(files.count - 5) more" : ""
            return "Working tree is dirty: \(head)\(suffix). Commit or stash before merging."
        case .branchNotFound(let name):
            return
                "Branch `\(name)` not found locally. "
                + "If it only exists on the remote: `git fetch && git checkout \(name)` in the terminal."
        case .notFastForward(let defaultBranch, let issueBranch):
            return
                "Cannot fast-forward: `\(defaultBranch)` has commits since `\(issueBranch)` was branched off. "
                + "Rebase `\(issueBranch)` onto `\(defaultBranch)` and retry."
        case .checkoutFailed(let stderr):
            return "git checkout failed: \(stderr)"
        case .mergeFailed(let mode, let stderr):
            switch mode {
            case .fastForward:
                return "git merge --ff-only failed: \(stderr)"
            case .squash:
                // Covers both squash steps (merge --squash and commit), so the
                // message names the operation, not a single git invocation.
                return "Squash merge failed: \(stderr)"
            }
        }
    }
}

nonisolated struct GitMergeOutcome: Sendable, Equatable {
    // nil = branch delete not requested OR succeeded. Non-nil = delete failed
    // after a successful merge; UI surfaces this as a non-fatal banner.
    let branchDeleteError: String?
}

nonisolated protocol GitMergeRunning: Sendable {
    func mergeIssueBranch(
        repoURL: URL,
        defaultBranch: String,
        issueBranch: String,
        mode: GitMergeMode,
        commitSubject: String?,
        deleteBranch: Bool
    ) async throws -> GitMergeOutcome
}

nonisolated struct GitMergeRunner: GitMergeRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func mergeIssueBranch(
        repoURL: URL,
        defaultBranch: String,
        issueBranch: String,
        mode: GitMergeMode,
        commitSubject: String?,
        deleteBranch: Bool
    ) async throws -> GitMergeOutcome {
        guard let binary = resolveBinary() else {
            throw GitMergeError.gitNotFound
        }
        try await runPreChecks(
            binary: binary, repoURL: repoURL,
            defaultBranch: defaultBranch, issueBranch: issueBranch)
        try await checkout(binary: binary, repoURL: repoURL, branch: defaultBranch)
        switch mode {
        case .fastForward:
            try await fastForwardMerge(binary: binary, repoURL: repoURL, issueBranch: issueBranch)
        case .squash:
            try await squashMerge(
                binary: binary, repoURL: repoURL,
                issueBranch: issueBranch, subject: commitSubject ?? "")
        }
        let deleteError =
            deleteBranch
            ? await safeDeleteBranch(binary: binary, repoURL: repoURL, branch: issueBranch, mode: mode)
            : nil
        return GitMergeOutcome(branchDeleteError: deleteError)
    }

    // MARK: - Pre-checks

    private func runPreChecks(
        binary: URL,
        repoURL: URL,
        defaultBranch: String,
        issueBranch: String
    ) async throws {
        // 1. status --porcelain must be empty.
        let status = try await callGit(
            binary: binary, repoURL: repoURL, args: ["status", "--porcelain"])
        if !status.stdout.isEmpty {
            throw GitMergeError.workingTreeDirty(files: parsePorcelain(status.stdout))
        }

        // 2. Issue branch must exist locally. rev-parse exits non-zero if not.
        let branchProbe = try await callGit(
            binary: binary, repoURL: repoURL,
            args: ["rev-parse", "--verify", issueBranch])
        if branchProbe.exitCode != 0 {
            throw GitMergeError.branchNotFound(name: issueBranch)
        }

        // 3. Fast-forward must be possible: defaultBranch must be an ancestor
        //    of issueBranch. merge-base --is-ancestor: 0 = yes, 1 = no.
        let ffProbe = try await callGit(
            binary: binary, repoURL: repoURL,
            args: ["merge-base", "--is-ancestor", defaultBranch, issueBranch])
        if ffProbe.exitCode != 0 {
            throw GitMergeError.notFastForward(
                defaultBranch: defaultBranch, issueBranch: issueBranch)
        }
    }

    // MARK: - Merge sequence

    private func checkout(binary: URL, repoURL: URL, branch: String) async throws {
        let result = try await callGit(
            binary: binary, repoURL: repoURL, args: ["checkout", branch])
        if result.exitCode != 0 {
            throw GitMergeError.checkoutFailed(stderr: stderrString(result))
        }
    }

    private func fastForwardMerge(binary: URL, repoURL: URL, issueBranch: String) async throws {
        let result = try await callGit(
            binary: binary, repoURL: repoURL,
            args: ["merge", "--ff-only", issueBranch])
        if result.exitCode != 0 {
            throw GitMergeError.mergeFailed(mode: .fastForward, stderr: stderrString(result))
        }
    }

    private func squashMerge(
        binary: URL, repoURL: URL, issueBranch: String, subject: String
    ) async throws {
        // Defense in depth: the UI disables the merge button on an empty
        // subject, but never let `git commit -m ""` happen regardless.
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else {
            throw GitMergeError.mergeFailed(mode: .squash, stderr: "empty commit subject")
        }
        let merge = try await callGit(
            binary: binary, repoURL: repoURL,
            args: ["merge", "--squash", issueBranch])
        if merge.exitCode != 0 {
            throw GitMergeError.mergeFailed(mode: .squash, stderr: stderrString(merge))
        }
        let commit = try await callGit(
            binary: binary, repoURL: repoURL,
            args: ["commit", "-m", subject])
        if commit.exitCode != 0 {
            // "nothing to commit" lands on stdout, not stderr — fall back so
            // the banner never shows an empty reason.
            let stderr = stderrString(commit)
            throw GitMergeError.mergeFailed(
                mode: .squash, stderr: stderr.isEmpty ? stdoutString(commit) : stderr)
        }
    }

    private func safeDeleteBranch(
        binary: URL, repoURL: URL, branch: String, mode: GitMergeMode
    ) async -> String? {
        // After a squash, git considers the branch unmerged, so -d would
        // always fail. -D is safe here: the ancestor pre-check plus the
        // just-created squash commit guarantee the branch tree is contained
        // in the default branch.
        let flag = mode == .squash ? "-D" : "-d"
        do {
            let result = try await callGit(
                binary: binary, repoURL: repoURL, args: ["branch", flag, branch])
            if result.exitCode != 0 {
                return stderrString(result)
            }
            return nil
        } catch let error as GitProcessRunnerError {
            return error.displayMessage
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Helpers

    // Routes all calls through `-C <path>` like GitDiffRunner so we never
    // mutate Plumage's CWD. cwd:nil keeps the spawn inherit-from-parent
    // semantics; -C tells git to chdir before doing anything.
    private func callGit(binary: URL, repoURL: URL, args: [String]) async throws -> GitSpawnResult {
        try await runner.run(
            binaryURL: binary,
            args: ["-C", repoURL.path] + args,
            cwd: nil)
    }

    private func parsePorcelain(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            // Porcelain format: 2-char status + 1 space + path (e.g. " M foo",
            // "?? bar", "MM baz"). The status block is always 3 characters
            // wide before the path begins.
            guard line.count > 3 else { return String(line) }
            return String(line.dropFirst(3))
        }
    }

    private func stderrString(_ result: GitSpawnResult) -> String {
        String(decoding: result.stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stdoutString(_ result: GitSpawnResult) -> String {
        String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
