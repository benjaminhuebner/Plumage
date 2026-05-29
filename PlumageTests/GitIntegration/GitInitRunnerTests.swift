import Foundation
import Testing

@testable import Plumage

@Suite("GitInitRunner")
struct GitInitRunnerTests {
    private func tmpDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "GitInit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Initializes a real repo on the given default branch")
    func realInit() async throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GitInitRunner().initRepo(at: dir, defaultBranch: "main")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: ".git").path))
        let head = try String(contentsOf: dir.appending(path: ".git/HEAD"), encoding: .utf8)
        #expect(head.contains("refs/heads/main"))
    }

    @Test("Custom default branch is honored")
    func customBranch() async throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GitInitRunner().initRepo(at: dir, defaultBranch: "trunk")
        let head = try String(contentsOf: dir.appending(path: ".git/HEAD"), encoding: .utf8)
        #expect(head.contains("refs/heads/trunk"))
    }

    @Test("Passes the expected git arguments")
    func argsViaMock() async throws {
        let mock = MockGitProcessRunner()
        let runner = GitInitRunner(runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })
        try await runner.initRepo(at: URL(filePath: "/tmp/x"), defaultBranch: "main")
        #expect(mock.recordedCalls == [["init", "-b", "main"]])
    }

    @Test("Missing git binary throws gitNotFound")
    func gitNotFound() async {
        let runner = GitInitRunner(runner: MockGitProcessRunner(), resolveBinary: { nil })
        await #expect(throws: GitInitError.gitNotFound) {
            try await runner.initRepo(at: URL(filePath: "/tmp/x"), defaultBranch: "main")
        }
    }
}
