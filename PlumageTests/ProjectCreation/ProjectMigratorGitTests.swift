import Foundation
import Testing

@testable import Plumage

@Suite("ProjectMigrator git")
struct ProjectMigratorGitTests {
    private let fileManager = FileManager.default

    private func existingDir(name: String = "Acme") throws -> (root: URL, parent: URL) {
        let parent = fileManager.temporaryDirectory
            .appending(path: "MigrateGit-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = parent.appending(path: name, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, parent)
    }

    private func migrator(overrideRoot: URL? = nil) -> ProjectMigrator {
        ProjectMigrator(
            assetsRoot: RepoAssets.root,
            overrideRoot: overrideRoot,
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"))
    }

    // Fakes just enough of a repo for the subprocess-free `RepoStateReader`.
    private func fakeRepo(at root: URL, head: String) throws {
        let gitDir = root.appending(path: ".git", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try head.write(to: gitDir.appending(path: "HEAD"), atomically: true, encoding: .utf8)
    }

    private func spec(root: URL, git: MigrationGitSetup, name: String = "Acme") -> MigrationSpec {
        MigrationSpec(projectDirectory: root, kind: .macOS, name: name, tagline: "x", git: git)
    }

    private func configGit(_ bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appending(path: "config.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(obj["git"] as? [String: Any])
    }

    @Test("config default branch reflects the existing repo branch")
    func defaultBranchFromRepo() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        try fakeRepo(at: root, head: "ref: refs/heads/develop\n")
        let (created, _) = try await migrator().migrate(
            spec: spec(root: root, git: MigrationGitSetup(initIfMissing: false)))
        #expect(try configGit(created.bundle)["defaultBranch"] as? String == "develop")
    }

    @Test("No repo and no init keeps the default branch main and creates no .git")
    func defaultBranchMainWithoutRepo() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        let (created, _) = try await migrator().migrate(
            spec: spec(root: root, git: MigrationGitSetup(initIfMissing: false)))
        #expect(try configGit(created.bundle)["defaultBranch"] as? String == "main")
        #expect(!fileManager.fileExists(atPath: root.appending(path: ".git").path))
    }

    @Test("Existing repo excludes plumage/claude artifacts when kept out of git")
    func excludeVariants() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        try fakeRepo(at: root, head: "ref: refs/heads/main\n")
        _ = try await migrator().migrate(
            spec: spec(
                root: root,
                git: MigrationGitSetup(
                    initIfMissing: false, plumageInGit: false, claudeInGit: false,
                    createGitignore: false)))
        let exclude = try String(
            contentsOf: root.appending(path: ".git/info/exclude"), encoding: .utf8)
        let excludeLines = exclude.split(separator: "\n").map(String.init)
        #expect(excludeLines.contains("Acme.plumage/"))
        #expect(!excludeLines.contains(".plumage/"))  // obsolete dotfolder, no longer excluded
        #expect(excludeLines.contains(".claude/"))
        #expect(excludeLines.contains(".mcp.json"))
    }

    @Test("Existing repo writes no excludes when everything stays in git")
    func noExcludeWhenAllInGit() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        try fakeRepo(at: root, head: "ref: refs/heads/main\n")
        _ = try await migrator().migrate(
            spec: spec(
                root: root,
                git: MigrationGitSetup(
                    initIfMissing: false, plumageInGit: true, claudeInGit: true,
                    createGitignore: false)))
        let excludePath = root.appending(path: ".git/info/exclude").path
        if fileManager.fileExists(atPath: excludePath) {
            let exclude = try String(contentsOf: URL(filePath: excludePath), encoding: .utf8)
            let excludeLines = exclude.split(separator: "\n").map(String.init)
            #expect(!excludeLines.contains(".claude/"))
            #expect(!excludeLines.contains(".plumage/"))
            #expect(!excludeLines.contains("Acme.plumage/"))
        }
    }

    @Test("initIfMissing initializes a repo when none exists and applies excludes")
    func initWhenMissing() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        _ = try await migrator().migrate(
            spec: spec(
                root: root,
                git: MigrationGitSetup(
                    initIfMissing: true, plumageInGit: false, claudeInGit: true,
                    createGitignore: false)))
        #expect(fileManager.fileExists(atPath: root.appending(path: ".git").path))
        let exclude = try String(
            contentsOf: root.appending(path: ".git/info/exclude"), encoding: .utf8)
        let excludeLines = exclude.split(separator: "\n").map(String.init)
        #expect(excludeLines.contains("Acme.plumage/"))
        #expect(!excludeLines.contains(".plumage/"))  // obsolete dotfolder, no longer excluded
        #expect(!excludeLines.contains(".claude/"))
    }
}
