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
        toggles: ScaffoldToggles = ScaffoldToggles(), hookWirings: [HookWiring] = []
    ) -> ProjectScaffolder {
        ProjectScaffolder(
            assetsRoot: RepoAssets.root,
            overrideRoot: overrideRoot,
            toggles: toggles,
            hookWirings: hookWirings,
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
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/skills/plumage-plan/scripts/roadmap.py").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".mcp.json").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".swift-format").path))

        let hook = dir.appending(path: ".claude/hooks/format-swift.sh").path
        let perms = try fm.attributesOfItem(atPath: hook)[.posixPermissions] as? Int
        #expect(((perms ?? 0) & 0o111) != 0)
    }

    @Test("A custom template scaffolds its own effective content by template id")
    func customTemplateScaffoldsOwnContent() async throws {
        let fm = FileManager.default
        var catalog = TemplateCatalog.bundledDefault
        let descriptor = catalog.addTemplate(
            name: "My Custom", image: .symbol("doc"),
            categoryID: ProjectKindGroup.other.rawValue, startingFrom: .empty)

        // The custom template's own layer lives in the override store; its content
        // must surface in the composed CLAUDE.md (proving resolution by template id,
        // not by the `.other` kind it falls back to for the Swift-config gate).
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "CustomTemplate-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write(
            "%% LAYOUT %%\nCUSTOM_TEMPLATE_MARKER\n%% /LAYOUT %%\n", to: overrideRoot,
            rel: "templates/\(descriptor.id)/CLAUDE.md")

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        let scaffolder = ProjectScaffolder(
            assetsRoot: RepoAssets.root, overrideRoot: overrideRoot,
            toggles: ScaffoldToggles(), hookWirings: [],
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"),
            gitInitRunner: GitInitRunner(), catalog: catalog)
        _ = try await scaffolder.create(
            spec: NewProjectSpec(
                kind: .other, templateID: descriptor.id, name: "MyApp", tagline: "tl",
                projectDirectory: dir))

        let claudeMd = try String(
            contentsOf: dir.appending(path: ".claude/CLAUDE.md"), encoding: .utf8)
        #expect(claudeMd.contains("CUSTOM_TEMPLATE_MARKER"))
        // Still a valid project.
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/settings.json").path))
        #expect(fm.fileExists(atPath: dir.appending(path: "MyApp.plumage/config.json").path))
        // A custom template maps to `.other` ⇒ no Swift configs (minimal but valid).
        #expect(!fm.fileExists(atPath: dir.appending(path: ".swift-format").path))
    }

    @Test("A loose docs file with a base placeholder merges a layer block at scaffold")
    func looseDocPlaceholderMergesAtScaffold() async throws {
        let fm = FileManager.default
        var catalog = TemplateCatalog.bundledDefault
        let descriptor = catalog.addTemplate(
            name: "Merge Demo", image: .symbol("doc"),
            categoryID: ProjectKindGroup.other.rawValue, startingFrom: .empty)

        let overrideRoot = fm.temporaryDirectory.appending(
            path: "LooseMerge-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        // The custom template needs its own (empty) CLAUDE.md layer to compose.
        try write("", to: overrideRoot, rel: "templates/\(descriptor.id)/CLAUDE.md")
        // Base docs skeleton carries the placeholder; the template layer fills it.
        try write("# Refs\n\n<<<refs>>>\n", to: overrideRoot, rel: "docs/refs.md")
        try write(
            "%% refs %%\n- see PROJECT.md\n%% /refs %%\n", to: overrideRoot,
            rel: "templates/\(descriptor.id)/docs/refs.md")

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        let scaffolder = ProjectScaffolder(
            assetsRoot: RepoAssets.root, overrideRoot: overrideRoot,
            toggles: ScaffoldToggles(), hookWirings: [],
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"),
            gitInitRunner: GitInitRunner(), catalog: catalog)
        _ = try await scaffolder.create(
            spec: NewProjectSpec(
                kind: .other, templateID: descriptor.id, name: "MyApp", tagline: "tl",
                projectDirectory: dir))

        let doc = try String(
            contentsOf: dir.appending(path: ".claude/docs/refs.md"), encoding: .utf8)
        #expect(doc == "# Refs\n\n- see PROJECT.md\n")
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

    // Reconciliation: the legacy `ScaffoldToggles` stays the artifact disable
    // carrier even though Settings no longer exposes per-hook toggles. A hook the user
    // disabled (persisted to scaffold-toggles.json) must stay absent — from the tree
    // and from settings.json — through the catalog-driven path.
    @Test("A previously-disabled hook (persisted toggles) stays absent after reconciliation")
    func legacyDisabledHookStaysAbsent() async throws {
        let fm = FileManager.default
        let togglesURL = fm.temporaryDirectory
            .appending(path: "scaffold-toggles-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: togglesURL) }
        // Simulate the legacy persisted state: a user who disabled lint-swift.
        var seeded = ScaffoldToggles()
        seeded.setEnabled(.hooks, "lint-swift", false)
        try seeded.save(to: togglesURL)

        let loaded = try ScaffoldToggles.load(from: togglesURL)
        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(toggles: loaded).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        #expect(!fm.fileExists(atPath: dir.appending(path: ".claude/hooks/lint-swift.sh").path))
        let settings = try String(
            contentsOf: dir.appending(path: ".claude/settings.json"), encoding: .utf8)
        #expect(!settings.contains("lint-swift.sh"))
        // A non-disabled sibling hook is still scaffolded and wired.
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/hooks/format-swift.sh").path))
        #expect(settings.contains("format-swift.sh"))
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

    @Test("User-authored docs are union-written alongside the bundled ones")
    func unionWritesUserDocs() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "UnionOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write("# Guide\n", to: overrideRoot, rel: "docs/guide.md")

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        // The user doc sits alongside the bundled docs.
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/docs/guide.md").path))
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/docs/PROJECT.md").path))
    }

    @Test("A user hook is scaffolded and wired into settings.json")
    func userHookScaffoldsAndWires() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "HookOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write("#!/bin/sh\necho hi\n", to: overrideRoot, rel: "hooks/my-hook.sh")
        let wirings = [HookWiring(name: "my-hook", event: .preToolUse, matcher: "Edit|Write")]

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot, hookWirings: wirings).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        let hookPath = dir.appending(path: ".claude/hooks/my-hook.sh").path
        #expect(fm.fileExists(atPath: hookPath))
        let perms = try fm.attributesOfItem(atPath: hookPath)[.posixPermissions] as? Int
        #expect(((perms ?? 0) & 0o111) != 0)

        let settings = try String(
            contentsOf: dir.appending(path: ".claude/settings.json"), encoding: .utf8)
        #expect(settings.contains("my-hook.sh"))
        #expect(settings.contains("Edit|Write"))
    }

    @Test("A Python user hook is scaffolded as .py and wired at its .py path")
    func pythonUserHookScaffoldsAndWires() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "HookOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write("#!/usr/bin/env python3\nprint('hi')\n", to: overrideRoot, rel: "hooks/py-hook.py")
        let wirings = [
            HookWiring(name: "py-hook", event: .preToolUse, matcher: "Edit", fileName: "py-hook.py")
        ]

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(overrideRoot: overrideRoot, hookWirings: wirings).create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        let hookPath = dir.appending(path: ".claude/hooks/py-hook.py").path
        #expect(fm.fileExists(atPath: hookPath))
        #expect(!fm.fileExists(atPath: dir.appending(path: ".claude/hooks/py-hook.sh").path))
        let perms = try fm.attributesOfItem(atPath: hookPath)[.posixPermissions] as? Int
        #expect(((perms ?? 0) & 0o111) != 0)

        let settings = try String(
            contentsOf: dir.appending(path: ".claude/settings.json"), encoding: .utf8)
        #expect(settings.contains("py-hook.py"))
        #expect(!settings.contains("py-hook.sh"))
    }

    @Test("No override store: docs are the bundled set; no default .plumage/scripts")
    func emptyStoreDocsScriptsUnchanged() async throws {
        let fm = FileManager.default
        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder().create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        // roadmap.py ships with the plumage-plan skill; .plumage/scripts is only
        // created when the user adds their own scripts.
        #expect(
            fm.fileExists(
                atPath: dir.appending(path: ".claude/skills/plumage-plan/scripts/roadmap.py").path))
        #expect(!fm.fileExists(atPath: dir.appending(path: ".plumage/scripts").path))
        let docs = try fm.contentsOfDirectory(atPath: dir.appending(path: ".claude/docs").path)
        #expect(Set(docs) == ["PROJECT.md", "notes.md", "decisions.md", "decisions-archive.md"])
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

    @Test("Scaffolded CLAUDE.md merges the folder-per-layer fragments with no leftover tokens")
    func scaffoldedClaudeMdMerges() async throws {
        let dir = tmpProjectDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder().create(
            spec: NewProjectSpec(kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir))

        let md = try String(contentsOf: dir.appending(path: ".claude/CLAUDE.md"), encoding: .utf8)
        #expect(md.contains("Strict concurrency is on"))  // templates/swift-shared/CLAUDE.md
        #expect(md.contains("@Observable"))  // templates/apple-shared/CLAUDE.md
        #expect(md.contains("custom NSWindow chrome"))  // templates/macos/CLAUDE.md
        #expect(!md.contains("<<<"))  // every token resolved, no duplicate skeleton markers
    }

    private struct NoopGitInit: GitInitializing {
        func initRepo(at url: URL, defaultBranch: String) async throws {}
    }

    @Test("A saved config override wins over generation at scaffold")
    func configOverrideWins() async throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "ConfigOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        try write("CUSTOM-IGNORE\n", to: overrideRoot, rel: ".gitignore")
        try write("{ \"mcpServers\": { \"x\": { \"command\": \"run\" } } }", to: overrideRoot, rel: ".mcp.json")
        try write("{ \"custom\": true }", to: overrideRoot, rel: ".claude/settings.json")

        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(git: NoopGitInit(), overrideRoot: overrideRoot).create(
            spec: NewProjectSpec(
                kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir, git: GitSetup()))

        let gitignore = try String(contentsOf: dir.appending(path: ".gitignore"), encoding: .utf8)
        #expect(gitignore == "CUSTOM-IGNORE\n")
        let mcp = try String(contentsOf: dir.appending(path: ".mcp.json"), encoding: .utf8)
        #expect(mcp.contains("\"command\": \"run\""))
        let settings = try String(
            contentsOf: dir.appending(path: ".claude/settings.json"), encoding: .utf8)
        #expect(settings.contains("\"custom\": true"))
        // The minimal local settings file is still generated.
        #expect(fm.fileExists(atPath: dir.appending(path: ".claude/settings.local.json").path))
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

    @Test("A Swift project kept out of git excludes the bundle from SwiftLint")
    func swiftLintExcludesBundleWhenOutOfGit() async throws {
        let dir = tmpProjectDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(git: NoopGitInit()).create(
            spec: NewProjectSpec(
                kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir,
                git: GitSetup(plumageInGit: false)))
        let yaml = try String(
            contentsOf: dir.appending(path: ".swiftlint.yml"), encoding: .utf8)
        #expect(yaml.contains("MyApp.plumage/"))
    }

    @Test("A Swift project kept in git leaves the SwiftLint config untouched")
    func swiftLintUntouchedWhenInGit() async throws {
        let dir = tmpProjectDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(git: NoopGitInit()).create(
            spec: NewProjectSpec(
                kind: .macOS, name: "MyApp", tagline: "tl", projectDirectory: dir,
                git: GitSetup(plumageInGit: true)))
        let yaml = try String(
            contentsOf: dir.appending(path: ".swiftlint.yml"), encoding: .utf8)
        #expect(!yaml.contains("MyApp.plumage/"))
    }

    @Test("A non-Swift project out of git has no SwiftLint config to edit (no error)")
    func nonSwiftHasNoSwiftLintConfig() async throws {
        let fm = FileManager.default
        let dir = tmpProjectDir()
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        _ = try await scaffolder(git: NoopGitInit()).create(
            spec: NewProjectSpec(
                kind: .other, name: "Thing", tagline: "tl", projectDirectory: dir,
                git: GitSetup(plumageInGit: false)))
        #expect(!fm.fileExists(atPath: dir.appending(path: ".swiftlint.yml").path))
    }
}
