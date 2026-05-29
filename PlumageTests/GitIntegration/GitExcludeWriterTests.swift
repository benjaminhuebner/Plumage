import Foundation
import Testing

@testable import Plumage

@Suite("GitExcludeWriter")
struct GitExcludeWriterTests {
    // A throwaway repo skeleton: only `.git/` (the writer creates `info/`).
    private func tmpRepo(withInfo: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GitExclude-\(UUID().uuidString)", directoryHint: .isDirectory)
        let dir = withInfo ? root.appending(path: ".git/info") : root.appending(path: ".git")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return root
    }

    private func excludeContents(_ repo: URL) throws -> String {
        try String(contentsOf: repo.appending(path: ".git/info/exclude"), encoding: .utf8)
    }

    @Test("Appends the given paths")
    func appends() throws {
        let repo = try tmpRepo(withInfo: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        try GitExcludeWriter().append(paths: [".plumage/", "Acme.plumage/"], repoURL: repo)
        let content = try excludeContents(repo)
        #expect(content.contains(".plumage/"))
        #expect(content.contains("Acme.plumage/"))
    }

    @Test("Creates .git/info when missing")
    func createsInfoDir() throws {
        let repo = try tmpRepo(withInfo: false)
        defer { try? FileManager.default.removeItem(at: repo) }
        try GitExcludeWriter().append(paths: [".claude/", ".mcp.json"], repoURL: repo)
        let content = try excludeContents(repo)
        #expect(content.contains(".claude/"))
        #expect(content.contains(".mcp.json"))
    }

    @Test("Idempotent — repeated paths are not duplicated")
    func idempotent() throws {
        let repo = try tmpRepo(withInfo: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        let writer = GitExcludeWriter()
        try writer.append(paths: [".plumage/"], repoURL: repo)
        try writer.append(paths: [".plumage/", ".claude/"], repoURL: repo)
        let lines = try excludeContents(repo)
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces) == ".plumage/" }
        #expect(lines.count == 1)
        #expect(try excludeContents(repo).contains(".claude/"))
    }
}
