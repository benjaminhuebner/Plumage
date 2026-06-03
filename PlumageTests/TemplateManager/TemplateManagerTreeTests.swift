import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManagerModel content tree")
struct TemplateManagerTreeTests {
    private func makeModel() throws -> (model: TemplateManagerModel, override: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMTree-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = base.appending(path: "bundled", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: override, withIntermediateDirectories: true)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: nil),
            overrides: ScaffoldOverrides(bundledRoot: bundled, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json"))
        return (model, override, { try? fm.removeItem(at: base) })
    }

    private func child(_ nodes: [FileNode], named name: String) -> FileNode? {
        nodes.first { $0.name == name }
    }

    @Test("Base tree mirrors the output layout with a nested .claude subtree")
    func baseTreeNests() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        for (rel, body) in [
            ("docs/guide.md", "# Guide"), ("hooks/x.sh", "#!/bin/sh"),
            ("agents/a.md", "# A"), ("skills/my-skill/SKILL.md", "x"),
            ("skills/my-skill/ref.md", "ref"),
        ] {
            try ctx.model.overrides.writeOverride(body, toRelative: rel)
        }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let claude = try #require(child(ctx.model.contentTree, named: ".claude"))
        #expect(claude.isDirectory)
        // Directory children sort alphabetically after any files at the level.
        let skills = try #require(child(claude.children ?? [], named: "skills"))
        let mySkill = try #require(child(skills.children ?? [], named: "my-skill"))
        #expect(mySkill.isDirectory)
        let skillMd = try #require(child(mySkill.children ?? [], named: "SKILL.md"))
        // The leaf keeps its override-store relative path, not the output path.
        #expect(skillMd.relativePath == "skills/my-skill/SKILL.md")
        #expect(!skillMd.isDirectory)
        #expect(child(mySkill.children ?? [], named: "ref.md") != nil)
    }

    @Test("A folder aggregates overridden and needs-wiring state from its descendants")
    func folderAggregatesMarkers() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride("# Guide", toRelative: "docs/guide.md")
        try ctx.model.overrides.writeOverride("#!/bin/sh", toRelative: "hooks/x.sh")  // unwired hook
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let claude = try #require(child(ctx.model.contentTree, named: ".claude"))
        #expect(ctx.model.aggregateOverridden(claude))
        #expect(ctx.model.aggregateNeedsWiring(claude))

        let docs = try #require(child(claude.children ?? [], named: "docs"))
        #expect(ctx.model.aggregateOverridden(docs))
        #expect(!ctx.model.aggregateNeedsWiring(docs))  // docs has no hooks
    }

    @Test("An arbitrary file is created in the selected folder and keeps its literal name")
    func addArbitraryFileInFolder() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride("# Guide", toRelative: "docs/guide.md")
        ctx.model.selection = .base
        ctx.model.refreshContent()
        let docs = try #require(
            child(child(ctx.model.contentTree, named: ".claude")?.children ?? [], named: "docs"))
        ctx.model.selectedFile = docs

        let node = try #require(ctx.model.addUserFile(kind: .file, rawName: ".editorconfig"))
        #expect(node.relativePath == "docs/.editorconfig")  // literal name, no .md appended
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/.editorconfig"))
    }

    @Test("An empty folder is created relative to the selection and appears in the tree")
    func addEmptyFolder() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride("# Guide", toRelative: "docs/guide.md")
        ctx.model.selection = .base
        ctx.model.refreshContent()
        let docs = try #require(
            child(child(ctx.model.contentTree, named: ".claude")?.children ?? [], named: "docs"))
        ctx.model.selectedFile = docs

        let node = try #require(ctx.model.addUserFile(kind: .folder, rawName: "drafts"))
        #expect(node.isDirectory)
        #expect(node.relativePath == ".claude/docs/drafts")
        // The empty folder is enumerated and shows in the rebuilt tree.
        let claude = try #require(child(ctx.model.contentTree, named: ".claude"))
        let docsAfter = try #require(child(claude.children ?? [], named: "docs"))
        #expect(child(docsAfter.children ?? [], named: "drafts") != nil)
    }

    @Test("Flattened leaves cover every file and exclude directory nodes")
    func flattenedLeaves() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride("# Guide", toRelative: "docs/guide.md")
        try ctx.model.overrides.writeOverride("#!/bin/sh", toRelative: "hooks/x.sh")
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let paths = Set(ctx.model.contentFiles.map(\.relativePath))
        #expect(paths.contains("docs/guide.md"))
        #expect(paths.contains("hooks/x.sh"))
        #expect(ctx.model.contentFiles.allSatisfy { !$0.isDirectory })
    }
}
