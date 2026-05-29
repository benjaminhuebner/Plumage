import Foundation
import Testing

@testable import Plumage

@Suite("ProjectScaffolder")
struct ProjectScaffolderTests {
    private func tmpProjectDir() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "Scaffold-\(UUID().uuidString)/MyApp", directoryHint: .isDirectory)
    }

    private func scaffolder(git: any GitInitializing = GitInitRunner()) -> ProjectScaffolder {
        ProjectScaffolder(
            assetsRoot: RepoAssets.root,
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"),
            gitInitRunner: git)
    }

    @Test("Scaffolds the expected tree for macOS")
    func macOSTree() async throws {
        let dir = tmpProjectDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let created = try await scaffolder().create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        let fm = FileManager.default
        #expect(created.root == dir)
        #expect(created.bundle.lastPathComponent == "MyApp.plumage")
        #expect(fm.fileExists(atPath: dir.appending(path: "MyApp.plumage/config.json").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/CLAUDE.md").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/settings.json").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/skills/plumage-implement/SKILL.md").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".plumage/scripts/roadmap.py").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".mcp.json").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".swift-format").path))

        let hook = dir.appending(path: ".claude/hooks/format-swift.sh").path
        let perms = try fm.attributesOfItem(atPath: hook)[.posixPermissions] as? Int
        #expect(((perms ?? 0) & 0o111) != 0)
    }

    @Test(".other omits the Swift config files")
    func otherNoSwiftConfigs() async throws {
        let dir = tmpProjectDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder().create(
            spec: NewProjectSpec(kind: .other, name: "Thing", tagline: "tl", projectDirectory: dir))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: ".swift-format").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: ".swiftlint.yml").path))
    }

    @Test("Rejects a non-empty directory")
    func rejectsNonEmpty() async throws {
        let dir = tmpProjectDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appending(path: "existing.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        await #expect(throws: ProjectScaffoldError.directoryNotEmpty(dir)) {
            _ = try await scaffolder().create(
                spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))
        }
    }

    @Test("Removes a freshly created directory on failure")
    func cleanupOnFailure() async throws {
        let dir = tmpProjectDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let failingGit = GitInitRunner(resolveBinary: { nil })
        let spec = NewProjectSpec(
            kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir, git: GitSetup())
        await #expect(throws: GitInitError.gitNotFound) {
            _ = try await scaffolder(git: failingGit).create(spec: spec)
        }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}
