import Foundation
import Testing

@testable import Plumage

@Suite("GitStatusRunner.parse")
struct GitStatusRunnerParseTests {
    @Test("empty output parses to empty list")
    func emptyOutput() throws {
        let result = try GitStatusRunner.parse(Data())
        #expect(result.isEmpty)
    }

    @Test("single modified file in working tree")
    func singleModifiedUnstaged() throws {
        let raw = " M Plumage/Foo.swift\u{0}"
        let result = try GitStatusRunner.parse(Data(raw.utf8))
        #expect(result.count == 1)
        #expect(result[0].path == "Plumage/Foo.swift")
        #expect(result[0].stagedStatus == " ")
        #expect(result[0].unstagedStatus == "M")
        #expect(result[0].isStaged == false)
        #expect(result[0].isUntracked == false)
        #expect(result[0].badge == "M")
    }

    @Test("staged add + unstaged modify mixes correctly")
    func stagedAndModified() throws {
        let raw = "MM Plumage/Bar.swift\u{0}A  Plumage/New.swift\u{0}"
        let result = try GitStatusRunner.parse(Data(raw.utf8))
        #expect(result.count == 2)
        #expect(result[0].stagedStatus == "M")
        #expect(result[0].unstagedStatus == "M")
        #expect(result[0].badge == "M")
        #expect(result[0].isStaged)
        #expect(result[1].stagedStatus == "A")
        #expect(result[1].unstagedStatus == " ")
        #expect(result[1].badge == "A")
    }

    @Test("untracked file uses ?? slot")
    func untracked() throws {
        let raw = "?? Plumage/Untracked.swift\u{0}"
        let result = try GitStatusRunner.parse(Data(raw.utf8))
        #expect(result.count == 1)
        #expect(result[0].isUntracked)
        #expect(result[0].badge == "?")
    }

    @Test("deleted file in index")
    func stagedDelete() throws {
        let raw = "D  Plumage/Gone.swift\u{0}"
        let result = try GitStatusRunner.parse(Data(raw.utf8))
        #expect(result[0].stagedStatus == "D")
        #expect(result[0].badge == "D")
    }

    @Test("rename row carries originalPath from second NUL-terminated token")
    func renameWithOriginal() throws {
        // With -z: `XY <new>\0<orig>\0`. R-staged means moved-in-index.
        let raw = "R  Plumage/New.swift\u{0}Plumage/Old.swift\u{0}"
        let result = try GitStatusRunner.parse(Data(raw.utf8))
        #expect(result.count == 1)
        #expect(result[0].stagedStatus == "R")
        #expect(result[0].path == "Plumage/New.swift")
        #expect(result[0].originalPath == "Plumage/Old.swift")
    }

    @Test("unmerged paths (UU) parse without panic")
    func unmergedConflict() throws {
        let raw = "UU Plumage/Conflict.swift\u{0}"
        let result = try GitStatusRunner.parse(Data(raw.utf8))
        #expect(result[0].stagedStatus == "U")
        #expect(result[0].unstagedStatus == "U")
    }

    @Test("malformed short row throws typed error")
    func malformedShortRow() {
        let raw = "M\u{0}"
        #expect(throws: GitStatusError.self) {
            _ = try GitStatusRunner.parse(Data(raw.utf8))
        }
    }

    @Test("rename row missing original throws malformedOutput")
    func renameMissingOriginal() {
        let raw = "R  Plumage/New.swift\u{0}"
        #expect(throws: GitStatusError.self) {
            _ = try GitStatusRunner.parse(Data(raw.utf8))
        }
    }
}

@Suite("GitStatusRunner end-to-end (mock)")
struct GitStatusRunnerMockTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("gitNotFound short-circuits before any subprocess call")
    func gitNotFoundShortCircuits() async {
        let mock = MockGitProcessRunner()
        let runner = GitStatusRunner(runner: mock, resolveBinary: { nil })
        await #expect(throws: GitCommandError.gitNotFound) {
            _ = try await runner.run(repoURL: self.repoURL)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("non-zero exit propagates stderr")
    func nonZeroExitPropagates() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "status", "--porcelain=v1", "-z"]
        mock.exitCodeForArgs[args] = 128
        mock.stderrForArgs[args] = "fatal: not a git repository\n"
        let runner = GitStatusRunner(runner: mock, resolveBinary: { self.binaryURL })

        await #expect(throws: GitCommandError.self) {
            _ = try await runner.run(repoURL: self.repoURL)
        }
    }

    @Test("clean tree yields empty array")
    func cleanTree() async throws {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "status", "--porcelain=v1", "-z"]
        mock.stdoutForArgs[args] = ""
        let runner = GitStatusRunner(runner: mock, resolveBinary: { self.binaryURL })
        let result = try await runner.run(repoURL: repoURL)
        #expect(result.isEmpty)
    }
}
