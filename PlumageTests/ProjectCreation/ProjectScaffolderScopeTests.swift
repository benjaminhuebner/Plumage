import Foundation
import Testing

@testable import Plumage

// Scaffolding composes loose files from Base ∪ template ∪ member components, with the
// most-specific scope winning a clash — so a file authored in one tier reaches only the
// projects that own it (#00078).
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

    private func scaffolder(overrideRoot: URL) -> ProjectScaffolder {
        ProjectScaffolder(
            assetsRoot: RepoAssets.root, overrideRoot: overrideRoot,
            toggles: ScaffoldToggles(), hookWirings: [],
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"),
            gitInitRunner: GitInitRunner())
    }

    private func projectDir() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "ScopeProj-\(UUID().uuidString)/App", directoryHint: .isDirectory)
    }

    private func create(_ kind: ProjectKind, overrideRoot: URL) async throws -> URL {
        let dir = projectDir()
        _ = try await scaffolder(overrideRoot: overrideRoot).create(
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

    @Test("Most-specific scope wins a name clash: component > template > base")
    func precedenceComponentOverTemplateOverBase() async throws {
        let ov = makeOverrideRoot()
        defer { try? FileManager.default.removeItem(at: ov) }
        // `t.md`: base vs template — template wins. `c.md`: base/template/component — component wins.
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
            try String(contentsOf: macDir.appending(path: ".claude/docs/c.md"), encoding: .utf8) == "COMP-C")
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
