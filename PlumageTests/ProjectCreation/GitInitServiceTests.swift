import Foundation
import Testing
import os

@testable import Plumage

@Suite("GitInitService")
struct GitInitServiceTests {
    private final class InitRecorder: Sendable {
        private let branches = OSAllocatedUnfairLock<[String]>(initialState: [])
        func record(_ branch: String) { branches.withLock { $0.append(branch) } }
        var recorded: [String] { branches.withLock { $0 } }
    }

    private struct RecordingGitInit: GitInitializing {
        let recorder: InitRecorder
        func initRepo(at url: URL, defaultBranch: String) async throws {
            recorder.record(defaultBranch)
        }
    }

    private func tmpDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "GitInitSvc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("inits on main, then excludes the plumage bundle and claude when not included")
    func initsMainAndExcludes() async throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = InitRecorder()
        let service = GitInitService(gitInitRunner: RecordingGitInit(recorder: recorder))

        try await service.initializeRepo(
            at: dir, name: "Acme", plumageInGit: false, claudeInGit: false)

        #expect(recorder.recorded == ["main"])
        let exclude = try String(
            contentsOf: dir.appending(path: ".git/info/exclude"), encoding: .utf8)
        #expect(exclude.contains("Acme.plumage/"))
        #expect(exclude.contains(".claude/"))
        #expect(exclude.contains(".mcp.json"))
    }

    @Test("including plumage and claude keeps them out of the excludes")
    func includedFilesAreNotExcluded() async throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = GitInitService(gitInitRunner: RecordingGitInit(recorder: InitRecorder()))

        try await service.initializeRepo(
            at: dir, name: "Acme", plumageInGit: true, claudeInGit: true)

        let exclude =
            (try? String(contentsOf: dir.appending(path: ".git/info/exclude"), encoding: .utf8)) ?? ""
        #expect(!exclude.contains(".claude/"))
        #expect(!exclude.contains("Acme.plumage/"))
    }
}
