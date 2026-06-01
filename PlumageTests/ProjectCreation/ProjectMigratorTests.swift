import Foundation
import Testing

@testable import Plumage

@Suite("ProjectMigrator")
struct ProjectMigratorTests {
    private let fileManager = FileManager.default

    private func migrator() -> ProjectMigrator {
        ProjectMigrator(
            assetsRoot: RepoAssets.root,
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"))
    }

    // A unique, already-existing project directory plus its parent (caller
    // defers removal of `parent`).
    private func existingDir(name: String = "Acme") throws -> (root: URL, parent: URL) {
        let parent = fileManager.temporaryDirectory
            .appending(path: "Migrate-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = parent.appending(path: name, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, parent)
    }

    private func spec(root: URL, kind: ProjectKind = .swiftCLI, name: String = "Acme") -> MigrationSpec {
        MigrationSpec(
            projectDirectory: root, kind: kind, name: name, tagline: "An app",
            git: MigrationGitSetup(initIfMissing: false))
    }

    @Test("Migrates a non-empty folder into a project that opens via the existing path")
    func migratesAndOpens() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        try "print(\"hi\")".write(
            to: root.appending(path: "main.swift"), atomically: true, encoding: .utf8)

        let (created, _) = try await migrator().migrate(spec: spec(root: root))

        #expect(created.root == root)
        let resolved = try BundleResolver.resolve(from: created.root)
        let config = try ConfigLoader.load(atBundle: resolved.bundle)
        #expect(config.name == "Acme")
        #expect(config.schemaVersion <= SchemaVersion.current)
        // The user's pre-existing file is untouched.
        #expect(
            try String(contentsOf: root.appending(path: "main.swift"), encoding: .utf8)
                == "print(\"hi\")")
    }

    @Test("config.json is always created")
    func configAlwaysCreated() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        let (_, report) = try await migrator().migrate(spec: spec(root: root))
        #expect(fileManager.fileExists(atPath: root.appending(path: "Acme.plumage/config.json").path))
        #expect(report.added.contains("Acme.plumage/config.json"))
    }

    @Test("Pre-existing CLAUDE.md and .gitignore are preserved byte-for-byte and reported as skipped")
    func preservesExistingFiles() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }

        let claudeDir = root.appending(path: ".claude", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let userClaudeMd = "# My own CLAUDE.md\nDo not touch.\n"
        try userClaudeMd.write(
            to: claudeDir.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        let userGitignore = "build/\nmy-secret\n"
        try userGitignore.write(
            to: root.appending(path: ".gitignore"), atomically: true, encoding: .utf8)

        let (_, report) = try await migrator().migrate(spec: spec(root: root))

        #expect(
            try String(contentsOf: claudeDir.appending(path: "CLAUDE.md"), encoding: .utf8)
                == userClaudeMd)
        #expect(
            try String(contentsOf: root.appending(path: ".gitignore"), encoding: .utf8)
                == userGitignore)
        #expect(report.skipped.contains(".claude/CLAUDE.md"))
        #expect(report.skipped.contains(".gitignore"))
        // Fresh artifacts are still added alongside the preserved ones.
        #expect(report.added.contains(".claude/settings.json"))
    }

    @Test("A folder that already holds a .plumage bundle throws alreadyPlumage")
    func alreadyPlumageThrows() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        let bundle = root.appending(path: "Existing.plumage", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)

        let error = await #expect(throws: ProjectMigrateError.self) {
            _ = try await migrator().migrate(spec: spec(root: root))
        }
        guard case .alreadyPlumage(let found) = error else {
            Issue.record("expected alreadyPlumage, got \(String(describing: error))")
            return
        }
        #expect(found.lastPathComponent == "Existing.plumage")
    }

    @Test("A nonexistent directory throws directoryMissing")
    func directoryMissingThrows() async throws {
        let root = fileManager.temporaryDirectory.appending(path: "nope-\(UUID().uuidString)")
        await #expect(throws: ProjectMigrateError.directoryMissing(root)) {
            _ = try await migrator().migrate(spec: spec(root: root))
        }
    }

    @Test(".other omits the Swift config files")
    func otherOmitsSwiftConfigs() async throws {
        let (root, parent) = try existingDir()
        defer { try? fileManager.removeItem(at: parent) }
        _ = try await migrator().migrate(spec: spec(root: root, kind: .other))
        #expect(!fileManager.fileExists(atPath: root.appending(path: ".swift-format").path))
        #expect(!fileManager.fileExists(atPath: root.appending(path: ".swiftlint.yml").path))
    }
}
