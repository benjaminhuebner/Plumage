import Foundation
import os

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
    private static let logger = Logger(subsystem: "com.plumage", category: "GitMergeRunner")

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
        // Both names reach git as positional args — reject option-shaped
        // values (frontmatter `branch:` is agent-written, config is on disk).
        guard GitBranchName.isSafe(defaultBranch) else {
            throw GitMergeError.branchNotFound(name: defaultBranch)
        }
        guard GitBranchName.isSafe(issueBranch) else {
            throw GitMergeError.branchNotFound(name: issueBranch)
        }
        try await runPreChecks(
            binary: binary, repoURL: repoURL,
            defaultBranch: defaultBranch, issueBranch: issueBranch)
        // Remember where the user was: a failed merge must not strand them
        // on the default branch when they started somewhere else.
        let originalBranch = await currentBranch(binary: binary, repoURL: repoURL)
        try await checkout(binary: binary, repoURL: repoURL, branch: defaultBranch)
        do {
            switch mode {
            case .fastForward:
                try await fastForwardMerge(
                    binary: binary, repoURL: repoURL, issueBranch: issueBranch)
            case .squash:
                try await squashMerge(
                    binary: binary, repoURL: repoURL,
                    issueBranch: issueBranch, subject: commitSubject ?? "")
            }
        } catch {
            await rollBack(
                binary: binary, repoURL: repoURL,
                originalBranch: originalBranch, defaultBranch: defaultBranch)
            throw error
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
        //    of issueBranch. merge-base --is-ancestor: 0 = yes, 1 = no,
        //    anything else (128: bad ref) is a different failure — reporting
        //    it as "not fast-forward" sent users rebasing for a typo.
        let ffProbe = try await callGit(
            binary: binary, repoURL: repoURL,
            args: ["merge-base", "--is-ancestor", defaultBranch, issueBranch])
        if ffProbe.exitCode == 1 {
            throw GitMergeError.notFastForward(
                defaultBranch: defaultBranch, issueBranch: issueBranch)
        }
        if ffProbe.exitCode != 0 {
            throw GitMergeError.branchNotFound(name: defaultBranch)
        }
    }

    // Pre-checks guarantee a clean tree, so anything dirty is merge residue —
    // without `reset --merge`, checkout would carry a staged squash along.
    // Restore failures only log: the merge error the caller sees outranks them.
    private func rollBack(
        binary: URL, repoURL: URL, originalBranch: String?, defaultBranch: String
    ) async {
        let reset = try? await callGit(
            binary: binary, repoURL: repoURL, args: ["reset", "--merge"])
        guard let reset, reset.exitCode == 0 else {
            Self.logger.error("rollback: reset --merge failed, staying on default branch")
            return
        }
        guard let originalBranch, originalBranch != defaultBranch else { return }
        let checkout = try? await callGit(
            binary: binary, repoURL: repoURL, args: ["checkout", originalBranch])
        guard let checkout, checkout.exitCode == 0 else {
            Self.logger.error("rollback: could not restore original branch, staying on default branch")
            return
        }
    }

    // Best-effort: nil when HEAD is detached or rev-parse fails — the
    // rollback path simply skips restoring in that case.
    private func currentBranch(binary: URL, repoURL: URL) async -> String? {
        guard
            let result = try? await callGit(
                binary: binary, repoURL: repoURL,
                args: ["symbolic-ref", "--short", "-q", "HEAD"]),
            result.exitCode == 0
        else { return nil }
        let name = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
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
