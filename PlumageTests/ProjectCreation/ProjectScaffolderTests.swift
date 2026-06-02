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

    @Test("No agents in the override store: no .claude/agents directory is created")
    func noAgentsNoDir() async throws {
        let fm = FileManager.default
        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder().create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))
        #expect(!fm.fileExists(atPath: dir.appending(path: ".claude/agents").path))
    }

    @Test("User-authored docs and scripts are union-written alongside the bundled ones")
    func unionWritesUserDocsAndScripts() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "UnionOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write("# Guide\n", to: overrideRoot, rel: "docs/guide.md")
        try write("#!/bin/sh\necho deploy\n", to: overrideRoot, rel: "plumage/deploy.sh")

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        // The user doc sits alongside the bundled docs.
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/docs/guide.md").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/docs/PROJECT.md").path))
        // The user script is written executable; the bundled roadmap.py stays.
        let scriptPath = dir.appending(path: ".plumage/scripts/deploy.sh").path
        #expect(fm.fileExists(atPath: scriptPath))
        let perms = try fm.attributesOfItem(atPath: scriptPath)[.posixPermissions] as? Int
        #expect(((perms ?? 0) & 0o111) != 0)
        #expect(fm.fileExists(atPath: dir.appending(path: ".plumage/scripts/roadmap.py").path))
    }

    @Test("No override store: docs and scripts are exactly the bundled set")
    func emptyStoreDocsScriptsUnchanged() async throws {
        let fm = FileManager.default
        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder().create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        let scripts = try fm.contentsOfDirectory(atPath: dir.appending(path: ".plumage/scripts").path)
        #expect(Set(scripts) == ["roadmap.py"])
        let docs = try fm.contentsOfDirectory(atPath: dir.appending(path: ".claude/docs").path)
        #expect(Set(docs) == ["PROJECT.md", "notes.md", "decisions.md"])
    }

    @Test("A user-authored skill is scaffolded from the override store, tree intact")
    func userSkillScaffolds() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "SkillOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write("---\nname: my-skill\n---\n# my-skill\n", to: overrideRoot, rel: "skills/my-skill/SKILL.md")
        try write("echo hi\n", to: overrideRoot, rel: "skills/my-skill/scripts/run.sh")

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/skills/my-skill/SKILL.md").path))
        let scriptPath = dir.appending(path: ".claude/skills/my-skill/scripts/run.sh").path
        #expect(fm.fileExists(atPath: scriptPath))
        let perms = try fm.attributesOfItem(atPath: scriptPath)[.posixPermissions] as? Int
        #expect(((perms ?? 0) & 0o111) != 0)
        // Bundled skills still scaffold alongside the user one.
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/skills/plumage-implement/SKILL.md").path))
    }

    @Test("A disabled user skill is absent from the scaffolded tree")
    func disabledUserSkillOmitted() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "SkillOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write("---\nname: my-skill\n---\n", to: overrideRoot, rel: "skills/my-skill/SKILL.md")
        var toggles = ScaffoldToggles()
        toggles.setEnabled(.skills, "my-skill", false)

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot, toggles: toggles).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))
        #expect(!fm.fileExists(atPath: dir.appending(path: ".claude/skills/my-skill").path))
    }

    private func write(_ contents: String, to root: URL, rel: String) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("Enabled user agents are written to .claude/agents; a disabled one is not")
    func writesEnabledAgents() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "AgentsOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        let agentsDir = overrideRoot.appending(path: "agents", directoryHint: .isDirectory)
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try "# Reviewer agent\n".write(
            to: agentsDir.appending(path: "reviewer.md"), atomically: true, encoding: .utf8)
        try "# Planner agent\n".write(
            to: agentsDir.appending(path: "planner.md"), atomically: true, encoding: .utf8)

        var toggles = ScaffoldToggles()
        toggles.setEnabled(.agents, "planner.md", false)

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot, toggles: toggles).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        let written = try String(
            contentsOf: dir.appending(path: ".claude/agents/reviewer.md"), encoding: .utf8)
        #expect(written.contains("Reviewer agent"))
        #expect(!fm.fileExists(atPath: dir.appending(path: ".claude/agents/planner.md").path))
    }
}
