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
            args: ["-C", repoURL.path, "push"],
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

    @Test("push without upstream auto-retries with --set-upstream and surfaces retry event")
    func noUpstreamRetry() async throws {
        let mock = MockGitProcessStreamer()
        // First attempt: git push exits 128 with the canonical no-upstream stderr.
        mock.enqueue(
            args: ["-C", repoURL.path, "push"],
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

    @Test("push failure without no-upstream pattern does not retry")
    func nonUpstreamFailureNoRetry() async throws {
        let mock = MockGitProcessStreamer()
        mock.enqueue(
            args: ["-C", repoURL.path, "push"],
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
            args: ["-C", repoURL.path, "push"],
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
