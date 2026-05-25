import Foundation

nonisolated enum GitMergeError: Error, Sendable, Equatable {
    case gitNotFound
    case workingTreeDirty(files: [String])
    case branchNotFound(name: String)
    case notFastForward(defaultBranch: String, issueBranch: String)
    case checkoutFailed(stderr: String)
    case mergeFailed(stderr: String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` nicht gefunden — Command-Line-Tools installiert?"
        case .workingTreeDirty(let files):
            let head = files.prefix(5).joined(separator: ", ")
            let suffix = files.count > 5 ? " …und \(files.count - 5) weitere" : ""
            return "Working tree ist dirty: \(head)\(suffix). Commit oder stash vor dem Merge."
        case .branchNotFound(let name):
            return
                "Branch `\(name)` lokal nicht gefunden. "
                + "Wenn er nur remote lebt: `git fetch && git checkout \(name)` im Terminal."
        case .notFastForward(let defaultBranch, let issueBranch):
            return
                "Cannot fast-forward: `\(defaultBranch)` hat Commits seit `\(issueBranch)` abgezweigt wurde. "
                + "Rebase `\(issueBranch)` auf `\(defaultBranch)` und retry."
        case .checkoutFailed(let stderr):
            return "git checkout fehlgeschlagen: \(stderr)"
        case .mergeFailed(let stderr):
            return "git merge --ff-only fehlgeschlagen: \(stderr)"
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
        deleteBranch: Bool
    ) async throws -> GitMergeOutcome {
        guard let binary = resolveBinary() else {
            throw GitMergeError.gitNotFound
        }
        try await runPreChecks(
            binary: binary, repoURL: repoURL,
            defaultBranch: defaultBranch, issueBranch: issueBranch)
        try await checkout(binary: binary, repoURL: repoURL, branch: defaultBranch)
        try await fastForwardMerge(binary: binary, repoURL: repoURL, issueBranch: issueBranch)
        let deleteError =
            deleteBranch
            ? await safeDeleteBranch(binary: binary, repoURL: repoURL, branch: issueBranch)
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
            throw GitMergeError.mergeFailed(stderr: stderrString(result))
        }
    }

    private func safeDeleteBranch(binary: URL, repoURL: URL, branch: String) async -> String? {
        do {
            let result = try await callGit(
                binary: binary, repoURL: repoURL, args: ["branch", "-d", branch])
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
}
