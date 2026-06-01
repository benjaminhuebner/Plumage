import Foundation
import Testing

@testable import Plumage

@Suite("ProjectScaffolder")
struct ProjectScaffolderTests {
    private func tmpProjectDir() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "Scaffold-\(UUID().uuidString)/MyApp", directoryHint: .isDirectory)
    }

    private func scaffolder(
        git: any GitInitializing = GitInitRunner(), overrideRoot: URL? = nil,
        toggles: ScaffoldToggles = ScaffoldToggles()
    ) -> ProjectScaffolder {
        ProjectScaffolder(
            assetsRoot: RepoAssets.root,
            overrideRoot: overrideRoot,
            toggles: toggles,
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

    @Test("No override store: scaffolded files are byte-identical to the bundled originals")
    func noOverrideByteIdentical() async throws {
        let fm = FileManager.default
        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder().create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        // A hook, a config, a doc, and a skill script — one from each copy site.
        let checks: [(scaffolded: String, bundled: String)] = [
            (".claude/hooks/format-swift.sh", "hooks/format-swift.sh"),
            (".swift-format", "configs/swift-format"),
            (".claude/docs/PROJECT.md", "docs/PROJECT.md"),
            (
                ".claude/skills/plumage-implement/scripts/precommit-gate.sh",
                "skills/plumage-implement/scripts/precommit-gate.sh"
            ),
        ]
        for check in checks {
            let got = try Data(contentsOf: dir.appending(path: check.scaffolded))
            let want = try Data(contentsOf: RepoAssets.root.appending(path: check.bundled))
            #expect(got == want, "byte mismatch for \(check.scaffolded)")
        }
    }

    @Test("Override store: a scaffolded file uses the overridden content")
    func overriddenFileScaffolds() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "ScaffoldOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        let hookOverride = overrideRoot.appending(path: "hooks/format-swift.sh")
        try fm.createDirectory(
            at: hookOverride.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho MY_OVERRIDDEN_HOOK\n".write(
            to: hookOverride, atomically: true, encoding: .utf8)

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        let scaffolded = try String(
            contentsOf: dir.appending(path: ".claude/hooks/format-swift.sh"), encoding: .utf8)
        #expect(scaffolded.contains("MY_OVERRIDDEN_HOOK"))
    }

    @Test("A disabled hook and a disabled skill are absent from the scaffolded tree")
    func disabledTogglesOmitArtifacts() async throws {
        let fm = FileManager.default
        var toggles = ScaffoldToggles()
        toggles.setEnabled(.hooks, "format-swift", false)
        toggles.setEnabled(.skills, "plumage-review", false)

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(toggles: toggles).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        #expect(!fm.fileExists(atPath: dir.appending(path: ".claude/hooks/format-swift.sh").path))
        #expect(
            !fm.fileExists(atPath: dir.appending(path: ".claude/skills/plumage-review").path))
        // Non-disabled siblings are still present.
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/hooks/lint-swift.sh").path))
        #expect(
            fm.fileExists(atPath: dir.appending(path: ".claude/skills/plumage-implement/SKILL.md").path))
    }
}
