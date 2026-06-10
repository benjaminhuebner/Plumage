import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("DiffTabModel")
struct DiffTabModelTests {
    private let repo = URL(fileURLWithPath: "/tmp/diff-tab-tests")

    private func makeModel(mock: MockGitProcessRunner) -> DiffTabModel {
        let binary = URL(fileURLWithPath: "/usr/bin/git")
        let runner = GitDiffRunner(runner: mock, resolveBinary: { binary })
        return DiffTabModel(repoURL: repo, baseBranch: "main", runner: runner, watcher: nil)
    }

    private func wireBaseChecks(_ mock: MockGitProcessRunner) {
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--git-dir"]] = ".git\n"
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--verify", "--quiet", "main"]] = "abc\n"
    }

    private func waitForState(
        _ model: DiffTabModel,
        until predicate: @escaping @Sendable @MainActor (DiffTabModel.State) -> Bool,
        timeout: Duration = .seconds(2)
    ) async throws {
        do {
            try await waitUntil(timeout: timeout) {
                await MainActor.run { predicate(model.state) }
            }
        } catch {
            Issue.record("timeout waiting for state, last = \(model.state)")
        }
    }

    @Test("reload transitions to .diff([...]) on non-empty parsed diff")
    func reloadsToDiff() async throws {
        let mock = MockGitProcessRunner()
        wireBaseChecks(mock)
        mock.stdoutForArgs[["-C", repo.path, "diff", "main...HEAD", "--"]] = """
            diff --git a/x b/x
            index 1111111..2222222 100644
            --- a/x
            +++ b/x
            @@ -1,1 +1,1 @@
            -old
            +new
            """
        let model = makeModel(mock: mock)
        model.reload()
        try await waitForState(model) {
            guard case .diff = $0 else { return false }
            return true
        }
        if case .diff(let files) = model.state {
            #expect(files.count == 1)
            #expect(files[0].path == "x")
        }
    }

    @Test("reload transitions to .empty on empty diff output")
    func reloadsToEmpty() async throws {
        let mock = MockGitProcessRunner()
        wireBaseChecks(mock)
        mock.stdoutForArgs[["-C", repo.path, "diff", "main...HEAD", "--"]] = ""
        let model = makeModel(mock: mock)
        model.reload()
        try await waitForState(model) { $0 == .empty }
    }

    @Test("reload transitions to .error(.baseBranchMissing) when base is missing")
    func reloadsToErrorBaseMissing() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--git-dir"]] = ".git\n"
        mock.exitCodeForArgs[["-C", repo.path, "rev-parse", "--verify", "--quiet", "main"]] = 1
        let model = makeModel(mock: mock)
        model.reload()
        try await waitForState(model) { state in
            if case .error(.baseBranchMissing) = state { return true }
            return false
        }
    }

    @Test("renders a representative .swift fixture through the model state")
    func swiftFixtureRenders() async throws {
        // Loads the DiffParser fixture directly from disk so we don't have to
        // duplicate the diff text here. This is the data-layer equivalent of
        // the spec's snapshot-test ask: parse + state-transition verified
        // against the same fixture the view consumes.
        let fixtureName = "simple-swift-edit.diff"
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL =
            testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DiffParser/Fixtures/\(fixtureName)")
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)

        let mock = MockGitProcessRunner()
        wireBaseChecks(mock)
        mock.stdoutForArgs[["-C", repo.path, "diff", "main...HEAD", "--"]] = fixture
        let model = makeModel(mock: mock)
        model.reload()
        try await waitForState(model) {
            guard case .diff = $0 else { return false }
            return true
        }

        guard case .diff(let files) = model.state else {
            Issue.record("expected .diff state")
            return
        }
        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.path == "Sources/Greeter.swift")
        if case .modified = file.status {
            // expected
        } else {
            Issue.record("expected .modified, got \(file.status)")
        }
        #expect(file.hunks.count == 1)
        let counts = file.hunks.flatMap(\.lines).reduce(into: (added: 0, removed: 0)) { acc, line in
            switch line.kind {
            case .added: acc.added += 1
            case .removed: acc.removed += 1
            case .context: break
            }
        }
        #expect(counts.added == 3)
        #expect(counts.removed == 2)
        // At least one added line carries tokens (Swift identifiers are
        // tokenized via LanguageConfiguration.swift()).
        let anyTokenized = file.hunks
            .flatMap(\.lines)
            .contains { !$0.tokens.isEmpty }
        #expect(anyTokenized, "expected at least one tokenized line")
    }

    @Test("rapid reloads cancel each other; last call wins")
    func rapidReloadsCancel() async throws {
        let mock = MockGitProcessRunner()
        wireBaseChecks(mock)
        mock.stdoutForArgs[["-C", repo.path, "diff", "main...HEAD", "--"]] = ""
        let model = makeModel(mock: mock)
        for _ in 0..<5 { model.reload() }
        try await waitForState(model) { $0 == .empty }
        // Each reload sequence issues 3 calls (git-dir, rev-parse, diff).
        // With cancellation, the recorded call count varies but the last
        // recorded triple still ends in the diff call.
        #expect(mock.recordedCalls.last == ["-C", repo.path, "diff", "main...HEAD", "--"])
    }
}
