import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("GitCommitModel")
struct GitCommitModelTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")

    @Test("initial load populates files and seeds staged paths from index")
    func initialLoad() async throws {
        let status = MockGitStatusRunner()
        status.outputs[repoURL] = [
            GitFileStatus(
                path: "a.swift", stagedStatus: "M",
                unstagedStatus: " ", originalPath: nil),
            GitFileStatus(
                path: "b.swift", stagedStatus: " ",
                unstagedStatus: "M", originalPath: nil),
            GitFileStatus(
                path: "c.swift", stagedStatus: "?",
                unstagedStatus: "?", originalPath: nil),
        ]
        let diff = MockGitWorkingDiffRunner()
        let stage = MockGitStager()
        let commit = MockGitCommitter()
        let model = GitCommitModel(
            repoURL: repoURL,
            statusRunner: status,
            diffRunner: diff,
            stageRunner: stage,
            commitRunner: commit
        )

        await model.refreshFiles()

        #expect(model.files.count == 3)
        #expect(model.stagedPaths == ["a.swift"])
        #expect(model.selectedPath == "a.swift")
    }

    @Test("canCommit needs non-empty message AND at least one staged path")
    func canCommitGuards() async throws {
        let status = MockGitStatusRunner()
        status.outputs[repoURL] = [
            GitFileStatus(
                path: "a.swift", stagedStatus: "M",
                unstagedStatus: " ", originalPath: nil)
        ]
        let model = GitCommitModel(
            repoURL: repoURL,
            statusRunner: status,
            diffRunner: MockGitWorkingDiffRunner(),
            stageRunner: MockGitStager(),
            commitRunner: MockGitCommitter()
        )
        await model.refreshFiles()

        #expect(!model.canCommit)
        model.message = "feat: thing"
        #expect(model.canCommit)
        model.stagedPaths.removeAll()
        #expect(!model.canCommit)
    }

    @Test("commit calls stage + commit runners and transitions to .done on success")
    func commitHappyPath() async throws {
        let status = MockGitStatusRunner()
        status.outputs[repoURL] = [
            GitFileStatus(
                path: "a.swift", stagedStatus: "M",
                unstagedStatus: " ", originalPath: nil),
            GitFileStatus(
                path: "b.swift", stagedStatus: " ",
                unstagedStatus: "M", originalPath: nil),
        ]
        let stage = MockGitStager()
        let commit = MockGitCommitter()
        let model = GitCommitModel(
            repoURL: repoURL,
            statusRunner: status,
            diffRunner: MockGitWorkingDiffRunner(),
            stageRunner: stage,
            commitRunner: commit
        )
        await model.refreshFiles()

        model.stagedPaths = ["b.swift"]  // user unchecks a.swift, checks b.swift
        model.message = "feat: things"
        await model.commit()

        #expect(stage.staged == [["b.swift"]])
        #expect(stage.unstaged == [["a.swift"]])
        #expect(commit.commits.first?.message == "feat: things")
        if case .done = model.commitState {} else { Issue.record("expected .done") }
    }

    @Test("commit surfaces typed error and stays committable")
    func commitFailureMessage() async throws {
        let status = MockGitStatusRunner()
        status.outputs[repoURL] = [
            GitFileStatus(
                path: "a.swift", stagedStatus: "M",
                unstagedStatus: " ", originalPath: nil)
        ]
        let commit = MockGitCommitter()
        commit.error = .nonZeroExit(code: 1, stderr: "fatal: boom")
        let model = GitCommitModel(
            repoURL: repoURL,
            statusRunner: status,
            diffRunner: MockGitWorkingDiffRunner(),
            stageRunner: MockGitStager(),
            commitRunner: commit
        )
        await model.refreshFiles()
        model.message = "msg"
        await model.commit()

        if case .error(let message) = model.commitState {
            #expect(message.contains("boom"))
        } else {
            Issue.record("expected .error state")
        }
    }

    @Test("user toggles persist across refresh — unchecked file stays unchecked")
    func toggleSurvivesRefresh() async throws {
        let status = MockGitStatusRunner()
        status.outputs[repoURL] = [
            GitFileStatus(
                path: "a.swift", stagedStatus: "M",
                unstagedStatus: " ", originalPath: nil)
        ]
        let model = GitCommitModel(
            repoURL: repoURL,
            statusRunner: status,
            diffRunner: MockGitWorkingDiffRunner(),
            stageRunner: MockGitStager(),
            commitRunner: MockGitCommitter()
        )
        await model.refreshFiles()
        #expect(model.stagedPaths == ["a.swift"])

        model.toggleStaged("a.swift")  // user unchecks
        #expect(model.stagedPaths.isEmpty)

        await model.refreshFiles()
        // Without the persist-on-refresh logic this would jump back to ["a.swift"].
        #expect(model.stagedPaths.isEmpty)
    }

    @Test("status error surfaces in loadState")
    func statusErrorState() async throws {
        let status = MockGitStatusRunner()
        status.error = .nonZeroExit(code: 128, stderr: "fatal: nope")
        let model = GitCommitModel(
            repoURL: repoURL,
            statusRunner: status,
            diffRunner: MockGitWorkingDiffRunner(),
            stageRunner: MockGitStager(),
            commitRunner: MockGitCommitter()
        )
        await model.refreshFiles()
        if case .error(let message) = model.loadState {
            #expect(message.contains("nope"))
        } else {
            Issue.record("expected error state")
        }
    }
}

// MARK: - Mocks

private final class MockGitWorkingDiffRunner: GitWorkingDiffRunning, @unchecked Sendable {
    private let lock = NSLock()
    var workingOutputs: [String: String] = [:]
    var stagedOutputs: [String: String] = [:]

    func diffWorking(repoURL: URL, path: String) async throws -> String {
        lock.withLock { workingOutputs[path] ?? "" }
    }

    func diffStaged(repoURL: URL, path: String) async throws -> String {
        lock.withLock { stagedOutputs[path] ?? "" }
    }
}

private final class MockGitStager: GitStaging, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var staged: [[String]] = []
    private(set) var unstaged: [[String]] = []
    var error: GitStageError?

    func stage(repoURL: URL, paths: [String]) async throws {
        lock.withLock { staged.append(paths) }
        if let error { throw error }
    }

    func unstage(repoURL: URL, paths: [String]) async throws {
        lock.withLock { unstaged.append(paths) }
        if let error { throw error }
    }
}

private final class MockGitCommitter: GitCommitting, @unchecked Sendable {
    struct Call: Sendable { let message: String }

    private let lock = NSLock()
    private(set) var commits: [Call] = []
    var error: GitCommitError?

    func commit(repoURL: URL, message: String) async throws {
        lock.withLock { commits.append(Call(message: message)) }
        if let error { throw error }
    }
}
