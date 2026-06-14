import Foundation
import Testing

@testable import Plumage

// Scaffolding composes loose files from Base ∪ template ∪ member components, with the
// most-specific scope winning a clash — so a file authored in one tier reaches only the
// projects that own it.
@Suite("ProjectScaffolder scope composition (#00078)")
struct ProjectScaffolderScopeTests {
    private func makeOverrideRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "ScopeOv-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ body: String, to root: URL, rel: String) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func scaffolder(overrideRoot: URL, wirings: [HookWiring] = []) -> ProjectScaffolder {
        ProjectScaffolder(
            assetsRoot: RepoAssets.root, overrideRoot: overrideRoot,
            toggles: ScaffoldToggles(), hookWirings: wirings,
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"),
            gitInitRunner: GitInitRunner())
    }

    private func projectDir() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "ScopeProj-\(UUID().uuidString)/App", directoryHint: .isDirectory)
    }

    private func create(
        _ kind: ProjectKind, overrideRoot: URL, wirings: [HookWiring] = []
    ) async throws -> URL {
        let dir = projectDir()
        _ = try await scaffolder(overrideRoot: overrideRoot, wirings: wirings).create(
            spec: NewProjectSpec(kind: kind, name: "App", tagline: "tl", projectDirectory: dir))
        return dir
    }

    @Test("A template-scoped doc reaches that template's project, not another")
    func templateDocIsScopedToItsProjects() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("# Base", to: ov, rel: "docs/base.md")
        try write("# Mac", to: ov, rel: "templates/macOS/docs/mac-only.md")

        let macDir = try await create(.macOS, overrideRoot: ov)
        let iosDir = try await create(.iOS, overrideRoot: ov)
        defer {
            try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: iosDir.deletingLastPathComponent())
        }
        let fm = FileManager.default
        // Base doc reaches both; the mac-scoped doc reaches only the macOS project.
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/docs/base.md").path))
        #expect(fm.fileExists(atPath: iosDir.appending(path: ".claude/docs/base.md").path))
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/docs/mac-only.md").path))
        #expect(!fm.fileExists(atPath: iosDir.appending(path: ".claude/docs/mac-only.md").path))
    }

    @Test("A component-scoped doc reaches member templates only")
    func componentDocReachesMembersOnly() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("# Swift", to: ov, rel: "components/swift-shared/docs/swift-only.md")

        let macDir = try await create(.macOS, overrideRoot: ov)  // member of swift-shared
        let otherDir = try await create(.other, overrideRoot: ov)  // not a member
        defer {
            try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: otherDir.deletingLastPathComponent())
        }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/docs/swift-only.md").path))
        #expect(!fm.fileExists(atPath: otherDir.appending(path: ".claude/docs/swift-only.md").path))
    }

    @Test("Most-specific scope wins a name clash: template > component > base (#00084)")
    func precedenceTemplateOverComponentOverBase() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        // `t.md`: base vs template — template wins. `c.md`: base/component/template — the
        // template wins over the member component now.
        try write("BASE-T", to: ov, rel: "docs/t.md")
        try write("MAC-T", to: ov, rel: "templates/macOS/docs/t.md")
        try write("BASE-C", to: ov, rel: "docs/c.md")
        try write("MAC-C", to: ov, rel: "templates/macOS/docs/c.md")
        try write("COMP-C", to: ov, rel: "components/swift-shared/docs/c.md")

        let macDir = try await create(.macOS, overrideRoot: ov)
        defer { try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent()) }
        #expect(
            try String(contentsOf: macDir.appending(path: ".claude/docs/t.md"), encoding: .utf8) == "MAC-T")
        #expect(
            try String(contentsOf: macDir.appending(path: ".claude/docs/c.md"), encoding: .utf8) == "MAC-C")
    }

    @Test("A user's hand-built loose tree is reproduced in the project (#00078)")
    func arbitraryLooseTreeIsScaffolded() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("# box note", to: ov, rel: "mybox/note.md")  // base-scope arbitrary folder
        try write("ed", to: ov, rel: ".editorconfig")  // base-scope arbitrary root file
        try write("# t-box", to: ov, rel: "templates/macOS/tbox/deep.md")  // template-scope arbitrary

        let macDir = try await create(.macOS, overrideRoot: ov)
        let otherDir = try await create(.other, overrideRoot: ov)
        defer {
            try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: otherDir.deletingLastPathComponent())
        }
        let fm = FileManager.default
        // Base arbitrary reaches every project at the project root, preserving structure.
        #expect(fm.fileExists(atPath: macDir.appending(path: "mybox/note.md").path))
        #expect(fm.fileExists(atPath: macDir.appending(path: ".editorconfig").path))
        #expect(fm.fileExists(atPath: otherDir.appending(path: "mybox/note.md").path))
        // Template-scoped arbitrary reaches only its own template's projects.
        #expect(fm.fileExists(atPath: macDir.appending(path: "tbox/deep.md").path))
        #expect(!fm.fileExists(atPath: otherDir.appending(path: "tbox/deep.md").path))
    }

    @Test("A loose .claude/ file is reproduced at <project>/.claude/ (#00084)")
    func claudeRootArbitraryFileIsScaffolded() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("# loose", to: ov, rel: ".claude/bla.md")  // base-scope `.claude/` loose file
        try write("# t", to: ov, rel: "templates/macOS/.claude/tmac.md")  // template-scope `.claude/`

        let macDir = try await create(.macOS, overrideRoot: ov)
        let otherDir = try await create(.other, overrideRoot: ov)
        defer {
            try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: otherDir.deletingLastPathComponent())
        }
        let fm = FileManager.default
        // Base `.claude/` reaches every project under its real `.claude/` root.
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/bla.md").path))
        #expect(fm.fileExists(atPath: otherDir.appending(path: ".claude/bla.md").path))
        // Template-scoped `.claude/` reaches only its own template's projects.
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/tmac.md").path))
        #expect(!fm.fileExists(atPath: otherDir.appending(path: ".claude/tmac.md").path))
    }

    @Test("A tier settings.json override replaces that tier's hooks in the scaffolded settings")
    func tierSettingsOverrideReplacesHooksOnScaffold() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        // swift-shared auto-wires format-swift/lint-swift; its override is authoritative.
        try write(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"x/.claude/hooks/comp-custom.sh"}]}]}}"#,
            to: ov, rel: "components/swift-shared/.claude/settings.json")

        let macDir = try await create(.macOS, overrideRoot: ov)
        defer { try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent()) }
        let settings = try String(
            contentsOf: macDir.appending(path: ".claude/settings.json"), encoding: .utf8)
        #expect(settings.contains("comp-custom.sh"))
        #expect(!settings.contains("format-swift.sh"))
        #expect(!settings.contains("lint-swift.sh"))
        // Base is a different, non-overridden tier — its hooks still wire.
        #expect(settings.contains("force-plumage-skill.sh"))
    }

    @Test("No tier settings override scaffolds byte-identical settings.json")
    func noTierOverrideSettingsByteIdentical() async throws {
        let ov = makeOverrideRoot()
        let empty = makeOverrideRoot()
        defer {
            try? FileManager.default.removeItem(at: ov)
            try? FileManager.default.removeItem(at: empty)
        }
        // Unrelated tier content, but no tier settings.json override anywhere.
        try write("# doc", to: ov, rel: "components/swift-shared/docs/x.md")

        let withContent = try await create(.macOS, overrideRoot: ov)
        let plain = try await create(.macOS, overrideRoot: empty)
        defer {
            try? FileManager.default.removeItem(at: withContent.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: plain.deletingLastPathComponent())
        }
        let withContentSettings = try Data(
            contentsOf: withContent.appending(path: ".claude/settings.json"))
        let plainSettings = try Data(contentsOf: plain.appending(path: ".claude/settings.json"))
        #expect(withContentSettings == plainSettings)
    }

    @Test("A component-owned hook lands as file and settings entry in member projects only")
    func componentHookReachesMembersOnly() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("#!/bin/sh\n", to: ov, rel: "components/swift-shared/hooks/comp-hook.sh")
        let wirings = [HookWiring(name: "comp-hook", event: .stop)]

        let macDir = try await create(.macOS, overrideRoot: ov, wirings: wirings)
        let otherDir = try await create(.other, overrideRoot: ov, wirings: wirings)
        defer {
            try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: otherDir.deletingLastPathComponent())
        }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/hooks/comp-hook.sh").path))
        #expect(!fm.fileExists(atPath: otherDir.appending(path: ".claude/hooks/comp-hook.sh").path))
        let macSettings = try String(
            contentsOf: macDir.appending(path: ".claude/settings.json"), encoding: .utf8)
        let otherSettings = try String(
            contentsOf: otherDir.appending(path: ".claude/settings.json"), encoding: .utf8)
        #expect(macSettings.contains("comp-hook.sh"))
        #expect(!otherSettings.contains("comp-hook.sh"))
    }

    @Test("A template-owned hook lands as file and settings entry in its own projects only")
    func templateHookReachesOwnProjectsOnly() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("#!/bin/sh\n", to: ov, rel: "templates/macOS/hooks/tmpl-hook.sh")
        try write("#!/bin/sh\n", to: ov, rel: "hooks/base-hook.sh")
        let wirings = [
            HookWiring(name: "tmpl-hook", event: .stop),
            HookWiring(name: "base-hook", event: .stop),
        ]

        let macDir = try await create(.macOS, overrideRoot: ov, wirings: wirings)
        let iosDir = try await create(.iOS, overrideRoot: ov, wirings: wirings)
        defer {
            try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: iosDir.deletingLastPathComponent())
        }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/hooks/tmpl-hook.sh").path))
        #expect(!fm.fileExists(atPath: iosDir.appending(path: ".claude/hooks/tmpl-hook.sh").path))
        // The Base hook keeps firing everywhere.
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/hooks/base-hook.sh").path))
        #expect(fm.fileExists(atPath: iosDir.appending(path: ".claude/hooks/base-hook.sh").path))
        let iosSettings = try String(
            contentsOf: iosDir.appending(path: ".claude/settings.json"), encoding: .utf8)
        #expect(!iosSettings.contains("tmpl-hook.sh"))
        #expect(iosSettings.contains("base-hook.sh"))
    }

    @Test("A component hook lands only in .claude/hooks/ — never leaked to the project root")
    func componentHookDoesNotLeakToProjectRoot() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("#!/bin/sh\n", to: ov, rel: "components/swift-shared/hooks/comp-hook.sh")
        let wirings = [HookWiring(name: "comp-hook", event: .stop)]

        let macDir = try await create(.macOS, overrideRoot: ov, wirings: wirings)
        defer { try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent()) }
        let fm = FileManager.default
        // Routed through the typed hooks walk into .claude/hooks/ …
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/hooks/comp-hook.sh").path))
        // … never reproduced verbatim at the project root by the arbitrary-file walk.
        #expect(!fm.fileExists(atPath: macDir.appending(path: "hooks").path))
        #expect(!fm.fileExists(atPath: macDir.appending(path: "components").path))
        // A bundled config still reaches the root as a dotfile via effectiveConfigs,
        // not re-routed into a configs/ folder by the exclusion change.
        #expect(fm.fileExists(atPath: macDir.appending(path: ".swift-format").path))
        #expect(!fm.fileExists(atPath: macDir.appending(path: "configs").path))
    }

    @Test("A component-owned skill scaffolds into member projects only")
    func componentSkillReachesMembersOnly() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        try write("# Skill", to: ov, rel: "components/swift-shared/skills/comp-skill/SKILL.md")

        let macDir = try await create(.macOS, overrideRoot: ov)
        let otherDir = try await create(.other, overrideRoot: ov)
        defer {
            try? FileManager.default.removeItem(at: macDir.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: otherDir.deletingLastPathComponent())
        }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: macDir.appending(path: ".claude/skills/comp-skill/SKILL.md").path))
        #expect(!fm.fileExists(atPath: otherDir.appending(path: ".claude/skills/comp-skill/SKILL.md").path))
    }
}
