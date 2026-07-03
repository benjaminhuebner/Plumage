import Foundation
import Testing

@testable import Plumage

@Suite("GitSyncRunner: push happy path")
struct GitSyncRunnerPushTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("clean push streams lines and finishes with exit 0")
    func cleanPush() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(source: .stderr, text: "Enumerating objects: 5"),
                GitStreamLine(source: .stderr, text: "Writing objects: 100%"),
                GitStreamLine(source: .stdout, text: "To github.com:foo/bar.git"),
                GitStreamLine(source: .stdout, text: "   abc..def  main -> main"),
            ],
            exitCode: 0
        )
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main"))

        let lines = events.compactMap { event -> String? in
            if case .line(let line) = event { return line.text }
            return nil
        }
        #expect(lines.contains("Enumerating objects: 5"))
        #expect(lines.contains("   abc..def  main -> main"))

        guard case .finished(let exit) = events.last else {
            Issue.record("expected last event to be .finished")
            return
        }
        #expect(exit == 0)
    }

    @Test("a credential injects the inline helper args and token env, keeping the token out of argv")
    func credentialInjection() async throws {
        let mock = MockGitProcessStreamer()
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        let credential = GitPushCredential(login: "octocat", token: "ghp_secret_value")

        _ = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main", credential: credential))

        let args = try #require(mock.calls.first)
        #expect(Array(args.prefix(2)) == ["-c", "credential.helper="])
        #expect(Array(args.suffix(4)) == ["-C", repoURL.path, "push", "origin"])
        #expect(!args.contains { $0.contains("ghp_secret_value") })

        let environment = try #require(mock.environments.first ?? nil)
        #expect(environment[GitCredentialInjection.tokenEnvVar] == "ghp_secret_value")
    }

    @Test("push without upstream auto-retries with --set-upstream and surfaces retry event")
    func noUpstreamRetry() async throws {
        let mock = MockGitProcessStreamer()
        // First attempt: git push exits 128 with the canonical no-upstream stderr.
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(source: .stderr, text: "fatal: The current branch feature/x has no upstream branch."),
                GitStreamLine(source: .stderr, text: "To push the current branch and set the remote as upstream, use"),
                GitStreamLine(source: .stderr, text: "    git push --set-upstream origin feature/x"),
            ],
            exitCode: 128
        )
        // Retry: same command + --set-upstream origin <branch>, exit 0.
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "--set-upstream", "origin", "feature/x"],
            lines: [
                GitStreamLine(source: .stdout, text: "Branch 'feature/x' set up to track 'origin/feature/x'.")
            ],
            exitCode: 0
        )
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "feature/x"))

        let retryHit = events.contains { event in
            if case .retryingWithUpstream(let branch) = event { return branch == "feature/x" }
            return false
        }
        #expect(retryHit)

        guard case .finished(let exit) = events.last else {
            Issue.record("expected last event to be .finished")
            return
        }
        #expect(exit == 0)

        // Both subprocess invocations were recorded.
        #expect(mock.calls.count == 2)
    }

    @Test("option-shaped branch name skips the --set-upstream retry")
    func optionShapedBranchSkipsRetry() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(
                    source: .stderr,
                    text: "fatal: The current branch --force has no upstream branch."),
                GitStreamLine(
                    source: .stderr,
                    text: "    git push --set-upstream origin --force"),
            ],
            exitCode: 128
        )
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(operation: .push, repoURL: repoURL, currentBranch: "--force"))

        let retryHit = events.contains { event in
            if case .retryingWithUpstream = event { return true }
            return false
        }
        #expect(!retryHit)
        #expect(mock.calls.count == 1)
    }

    @Test("push failure without no-upstream pattern does not retry")
    func nonUpstreamFailureNoRetry() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(
                    source: .stderr,
                    text: "error: failed to push some refs to 'github.com:foo/bar.git'")
            ],
            exitCode: 1
        )
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main"))
        guard case .finished(let exit) = events.last else {
            Issue.record("expected last event to be .finished")
            return
        }
        #expect(exit == 1)
        #expect(mock.calls.count == 1)
    }
}

@Suite("GitSyncRunner: push options")
struct GitSyncRunnerPushOptionsTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("force maps to --force-with-lease before the remote positional")
    func forceFlag() async throws {
        let mock = MockGitProcessStreamer()
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        _ = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                pushOptions: GitPushOptions(remote: "origin", includeTags: false, force: true)))
        let args = try #require(mock.calls.first)
        #expect(args == ["-C", repoURL.path, "push", "--force-with-lease", "origin"])
    }

    @Test("tags maps to --follow-tags")
    func tagsFlag() async throws {
        let mock = MockGitProcessStreamer()
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        _ = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                pushOptions: GitPushOptions(remote: "origin", includeTags: true, force: false)))
        let args = try #require(mock.calls.first)
        #expect(args == ["-C", repoURL.path, "push", "--follow-tags", "origin"])
    }

    @Test("force and tags together keep a stable order, then the remote")
    func forceAndTags() async throws {
        let mock = MockGitProcessStreamer()
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        _ = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                pushOptions: GitPushOptions(remote: "upstream", includeTags: true, force: true)))
        let args = try #require(mock.calls.first)
        #expect(
            args == ["-C", repoURL.path, "push", "--force-with-lease", "--follow-tags", "upstream"])
    }

    @Test("a chosen non-origin remote is the positional target")
    func nonOriginRemote() async throws {
        let mock = MockGitProcessStreamer()
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        _ = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                pushOptions: GitPushOptions(remote: "fork", includeTags: false, force: false)))
        let args = try #require(mock.calls.first)
        #expect(args == ["-C", repoURL.path, "push", "fork"])
    }

    @Test("an option-shaped remote name is dropped, not injected as a flag")
    func unsafeRemoteDropped() async throws {
        let mock = MockGitProcessStreamer()
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        _ = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                pushOptions: GitPushOptions(
                    remote: "--upload-pack=evil", includeTags: false, force: false)))
        let args = try #require(mock.calls.first)
        #expect(args == ["-C", repoURL.path, "push"])
        #expect(!args.contains { $0.hasPrefix("--upload-pack") })
    }

    @Test("an unsafe remote that hits no-upstream does not run an injected set-upstream retry")
    func unsafeRemoteSkipsRetry() async throws {
        let mock = MockGitProcessStreamer()
        // First (and only) attempt: the unsafe remote is dropped, so bare `git push`
        // runs and fails with the canonical no-upstream stderr. The remote-safety
        // guard must then block the retry rather than inject `--set-upstream --exec=…`.
        mock.enqueue(
            args: ["-C", repoURL.path, "push"],
            lines: [
                GitStreamLine(source: .stderr, text: "fatal: The current branch main has no upstream branch."),
                GitStreamLine(source: .stderr, text: "    git push --set-upstream origin main"),
            ],
            exitCode: 128)
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        _ = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                pushOptions: GitPushOptions(
                    remote: "--upload-pack=evil", includeTags: false, force: false)))
        #expect(mock.calls.count == 1)
        #expect(!mock.calls.flatMap { $0 }.contains { $0.hasPrefix("--upload-pack") })
    }

    @Test("the set-upstream retry carries the chosen remote and the push flags")
    func retryCarriesOptions() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "--force-with-lease", "--follow-tags", "fork"],
            lines: [
                GitStreamLine(source: .stderr, text: "fatal: The current branch main has no upstream branch."),
                GitStreamLine(source: .stderr, text: "    git push --set-upstream fork main"),
            ],
            exitCode: 128)
        mock.enqueue(
            args: [
                "-C", repoURL.path, "push", "--force-with-lease", "--follow-tags",
                "--set-upstream", "fork", "main",
            ],
            lines: [GitStreamLine(source: .stdout, text: "Branch 'main' set up to track 'fork/main'.")],
            exitCode: 0)
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })
        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                pushOptions: GitPushOptions(remote: "fork", includeTags: true, force: true)))
        guard case .finished(let exit) = events.last else {
            Issue.record("expected .finished")
            return
        }
        #expect(exit == 0)
        #expect(mock.calls.count == 2)
    }
}

@Suite("GitSyncRunner: pull")
struct GitSyncRunnerPullTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("pull conflict surfaces the exit code, no retry")
    func pullConflictExitCode() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "pull"],
            lines: [
                GitStreamLine(source: .stderr, text: "CONFLICT (content): Merge conflict in foo.swift"),
                GitStreamLine(
                    source: .stderr, text: "Automatic merge failed; fix conflicts and then commit the result."),
            ],
            exitCode: 1
        )
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .pull, repoURL: repoURL, currentBranch: "main"))
        guard case .finished(let exit) = events.last else {
            Issue.record("expected last event to be .finished")
            return
        }
        #expect(exit == 1)
        #expect(mock.calls.count == 1)
    }
}

@Suite("GitSyncRunner: auth prompt detection")
struct GitSyncRunnerAuthTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("AuthPromptDetector matches common credential-prompt patterns")
    func detectorPatterns() {
        #expect(AuthPromptDetector.isAuthPrompt("Username for 'https://github.com':"))
        #expect(AuthPromptDetector.isAuthPrompt("Password for 'https://user@github.com':"))
        #expect(AuthPromptDetector.isAuthPrompt("fatal: could not read Username for"))
        #expect(
            AuthPromptDetector.isAuthPrompt(
                "fatal: could not read Username for 'https://gitlab.com': terminal prompts disabled"))
        #expect(!AuthPromptDetector.isAuthPrompt("Normal output line"))
    }

    @Test("push that emits a credential prompt yields .authPromptDetected before .finished")
    func authPromptDuringPush() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(source: .stderr, text: "Cloning into '...'"),
                GitStreamLine(source: .stderr, text: "Username for 'https://github.com': "),
                GitStreamLine(
                    source: .stderr,
                    text: "fatal: could not read Username for 'https://github.com': terminal prompts disabled"),
            ],
            exitCode: 128
        )
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main"))

        let promptIdx = try #require(
            events.firstIndex {
                if case .authPromptDetected = $0 { return true }
                return false
            })
        let finishedIdx = try #require(
            events.firstIndex {
                if case .finished = $0 { return true }
                return false
            })
        #expect(promptIdx < finishedIdx)

        // Auth-prompt path must NOT trigger the no-upstream retry, even if
        // the line contains "set-upstream" — push only ran once.
        #expect(mock.calls.count == 1)
    }

    @Test("PushAuthFailureDetector matches server-side auth rejections")
    func authFailureDetector() {
        #expect(
            PushAuthFailureDetector.looksLikeAuthFailure([
                "fatal: Authentication failed for 'https://github.com/x/y.git/'"
            ]))
        #expect(PushAuthFailureDetector.looksLikeAuthFailure(["remote: Invalid username or token."]))
        #expect(
            PushAuthFailureDetector.looksLikeAuthFailure(["remote: Permission to x/y.git denied to user."]))
        #expect(!PushAuthFailureDetector.looksLikeAuthFailure(["Everything up-to-date"]))
    }

    @Test("a rejected token with a credential surfaces .credentialRejected, no retry")
    func credentialRejected() async throws {
        let mock = MockGitProcessStreamer()
        let args =
            GitCredentialInjection.arguments(login: "octocat") + ["-C", repoURL.path, "push", "origin"]
        mock.enqueue(
            args: args,
            lines: [
                GitStreamLine(source: .stderr, text: "remote: Invalid username or token."),
                GitStreamLine(
                    source: .stderr,
                    text: "fatal: Authentication failed for 'https://github.com/octocat/repo.git/'"),
            ],
            exitCode: 128)
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                credential: GitPushCredential(login: "octocat", token: "ghp_dead")))

        let rejected = events.contains { event in
            if case .credentialRejected(let login) = event { return login == "octocat" }
            return false
        }
        #expect(rejected)
        #expect(mock.calls.count == 1)
    }

    @Test("an auth failure with no credential is not reported as credentialRejected")
    func noCredentialNoRejection() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(
                    source: .stderr,
                    text: "fatal: Authentication failed for 'https://github.com/x/y.git/'")
            ],
            exitCode: 128)
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(operation: .push, repoURL: repoURL, currentBranch: "main"))
        let rejected = events.contains { event in
            if case .credentialRejected = event { return true }
            return false
        }
        #expect(!rejected)
    }

    @Test("the no-upstream retry re-injects the credential helper args and token env")
    func retryCarriesCredential() async throws {
        let mock = MockGitProcessStreamer()
        let injection = GitCredentialInjection.arguments(login: "octocat")
        mock.enqueue(
            args: injection + ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(source: .stderr, text: "fatal: The current branch main has no upstream branch."),
                GitStreamLine(source: .stderr, text: "    git push --set-upstream origin main"),
            ],
            exitCode: 128)
        mock.enqueue(
            args: injection + ["-C", repoURL.path, "push", "--set-upstream", "origin", "main"],
            lines: [GitStreamLine(source: .stdout, text: "Branch 'main' set up to track 'origin/main'.")],
            exitCode: 0)
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                credential: GitPushCredential(login: "octocat", token: "ghp_secret_value")))

        guard case .finished(let exit) = events.last else {
            Issue.record("expected last event to be .finished")
            return
        }
        #expect(exit == 0)
        #expect(mock.calls.count == 2)

        let retryArgs = try #require(mock.calls.last)
        #expect(Array(retryArgs.prefix(2)) == ["-c", "credential.helper="])
        #expect(Array(retryArgs.suffix(4)) == ["push", "--set-upstream", "origin", "main"])
        #expect(!retryArgs.contains { $0.contains("ghp_secret_value") })

        let retryEnv = try #require(mock.environments.last ?? nil)
        #expect(retryEnv[GitCredentialInjection.tokenEnvVar] == "ghp_secret_value")
    }

    @Test("a credential rejected on the set-upstream retry still surfaces .credentialRejected")
    func retryCredentialRejected() async throws {
        let mock = MockGitProcessStreamer()
        let injection = GitCredentialInjection.arguments(login: "octocat")
        mock.enqueue(
            args: injection + ["-C", repoURL.path, "push", "origin"],
            lines: [
                GitStreamLine(source: .stderr, text: "fatal: The current branch main has no upstream branch."),
                GitStreamLine(source: .stderr, text: "    git push --set-upstream origin main"),
            ],
            exitCode: 128)
        mock.enqueue(
            args: injection + ["-C", repoURL.path, "push", "--set-upstream", "origin", "main"],
            lines: [
                GitStreamLine(
                    source: .stderr,
                    text: "fatal: Authentication failed for 'https://github.com/octocat/repo.git/'")
            ],
            exitCode: 128)
        let runner = GitSyncRunner(streamer: mock, resolveBinary: { self.binaryURL })

        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main",
                credential: GitPushCredential(login: "octocat", token: "ghp_dead")))

        let rejected = events.contains { event in
            if case .credentialRejected(let login) = event { return login == "octocat" }
            return false
        }
        #expect(rejected)
        #expect(mock.calls.count == 2)
    }
}

@Suite("GitSyncRunner: edge cases")
struct GitSyncRunnerEdgeTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")

    @Test("gitNotFound is surfaced as a stderr line + non-zero exit, not a thrown error")
    func gitNotFoundPath() async {
        let runner = GitSyncRunner(streamer: MockGitProcessStreamer(), resolveBinary: { nil })
        let events = await collect(
            runner.run(
                operation: .push, repoURL: repoURL, currentBranch: "main"))
        let last = events.last
        guard case .finished(let exit) = last else {
            Issue.record("expected .finished")
            return
        }
        #expect(exit == 127)
    }
}

// Helper: drain the AsyncStream into an array for assertions.
private func collect(_ stream: AsyncStream<GitSyncEvent>) async -> [GitSyncEvent] {
    var collected: [GitSyncEvent] = []
    for await event in stream { collected.append(event) }
    return collected
}
