import Foundation
import Testing

@testable import Plumage

@Suite("GitExcludeRenamer")
struct GitExcludeRenamerTests {
    private func tmpRepo(exclude: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GitExcludeRename-\(UUID().uuidString)", directoryHint: .isDirectory)
        let info = root.appending(path: ".git/info")
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        if let exclude {
            try exclude.write(to: info.appending(path: "exclude"), atomically: true, encoding: .utf8)
        }
        return root
    }

    private func excludeContents(_ repo: URL) throws -> String {
        try String(contentsOf: repo.appending(path: ".git/info/exclude"), encoding: .utf8)
    }

    @Test("rewrites the matching bundle line and leaves other lines intact")
    func rewritesMatchingLine() throws {
        let repo = try tmpRepo(
            exclude: """
                # git ls-files --others --exclude-from=.git/info/exclude
                .DS_Store
                Old.plumage/
                .build/
                """)
        defer { try? FileManager.default.removeItem(at: repo) }

        let changed = try GitExcludeRenamer().rename(
            oldBundleName: "Old", newBundleName: "New", repoURL: repo)

        #expect(changed)
        let content = try excludeContents(repo)
        #expect(content.contains("New.plumage/"))
        #expect(!content.contains("Old.plumage/"))
        // Unrelated lines survive verbatim.
        #expect(content.contains(".DS_Store"))
        #expect(content.contains(".build/"))
        #expect(content.contains("# git ls-files"))
    }

    @Test("matches a line with surrounding whitespace")
    func matchesWhitespacePaddedLine() throws {
        let repo = try tmpRepo(exclude: "  Old.plumage/  \n")
        defer { try? FileManager.default.removeItem(at: repo) }

        let changed = try GitExcludeRenamer().rename(
            oldBundleName: "Old", newBundleName: "New", repoURL: repo)

        #expect(changed)
        #expect(try excludeContents(repo).contains("New.plumage/"))
    }

    @Test("no-op when the exclude file is absent")
    func noOpWhenExcludeMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GitExcludeRename-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: ".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let changed = try GitExcludeRenamer().rename(
            oldBundleName: "Old", newBundleName: "New", repoURL: root)
        #expect(!changed)
    }

    @Test("no-op when the bundle line is not present, file unchanged")
    func noOpWhenLineAbsent() throws {
        let original = ".DS_Store\n.build/\n"
        let repo = try tmpRepo(exclude: original)
        defer { try? FileManager.default.removeItem(at: repo) }

        let changed = try GitExcludeRenamer().rename(
            oldBundleName: "Old", newBundleName: "New", repoURL: repo)

        #expect(!changed)
        #expect(try excludeContents(repo) == original)
    }

    @Test("no-op when old and new names are equal")
    func noOpWhenNamesEqual() throws {
        let repo = try tmpRepo(exclude: "Same.plumage/\n")
        defer { try? FileManager.default.removeItem(at: repo) }

        let changed = try GitExcludeRenamer().rename(
            oldBundleName: "Same", newBundleName: "Same", repoURL: repo)
        #expect(!changed)
    }

    @Test("only the exact bundle line is rewritten, not a substring match")
    func doesNotRewriteSubstringMatch() throws {
        // "OldProject.plumage/" must NOT match an "Old" rename.
        let repo = try tmpRepo(exclude: "OldProject.plumage/\n")
        defer { try? FileManager.default.removeItem(at: repo) }

        let changed = try GitExcludeRenamer().rename(
            oldBundleName: "Old", newBundleName: "New", repoURL: repo)

        #expect(!changed)
        #expect(try excludeContents(repo).contains("OldProject.plumage/"))
    }
}
