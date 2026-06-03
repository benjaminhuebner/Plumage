import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManagerModel editing")
struct TemplateManagerModelTests {
    private func makeModel() throws -> (
        model: TemplateManagerModel, bundled: URL, override: URL, cleanup: () -> Void
    ) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = base.appending(path: "bundled", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: override, withIntermediateDirectories: true)
        let overrides = ScaffoldOverrides(bundledRoot: bundled, overrideRoot: override)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: nil), overrides: overrides)
        return (model, bundled, override, { try? fm.removeItem(at: base) })
    }

    private func writeBundled(_ contents: String, rel: String, root: URL) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func node(rel: String, root: URL, isDirectory: Bool = false) -> FileNode {
        FileNode(
            url: root.appending(path: rel), relativePath: rel,
            name: (rel as NSString).lastPathComponent, isDirectory: isDirectory, children: nil)
    }

    @Test("Editing a bundled-backed file targets the override slot and seeds from bundled")
    func bundledBackedEditTargets() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try writeBundled("BUNDLED", rel: "templates/CLAUDE.md", root: ctx.bundled)

        ctx.model.beginEditing(node(rel: "templates/CLAUDE.md", root: ctx.bundled))

        #expect(ctx.model.editingFileURL == ctx.override.appending(path: "templates/CLAUDE.md"))
        #expect(ctx.model.editingFallbackURL == ctx.bundled.appending(path: "templates/CLAUDE.md"))
    }

    @Test("Editing a user-authored file has no bundled fallback")
    func userAuthoredHasNoFallback() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }

        ctx.model.beginEditing(node(rel: "docs/notes.md", root: ctx.override))

        #expect(ctx.model.editingFileURL == ctx.override.appending(path: "docs/notes.md"))
        #expect(ctx.model.editingFallbackURL == nil)
    }

    @Test("Clearing selection or selecting a directory clears the edit target")
    func clearsEditTarget() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try writeBundled("X", rel: "templates/CLAUDE.md", root: ctx.bundled)

        ctx.model.beginEditing(node(rel: "templates/CLAUDE.md", root: ctx.bundled))
        #expect(ctx.model.editingFileURL != nil)

        ctx.model.beginEditing(nil)
        #expect(ctx.model.editingFileURL == nil)
        #expect(ctx.model.editingFallbackURL == nil)

        ctx.model.beginEditing(node(rel: "skills", root: ctx.override, isDirectory: true))
        #expect(ctx.model.editingFileURL == nil)
    }

    // MARK: - Marker / reset / delete

    @Test("notifySaved marks a divergent override and unmarks an identical one")
    func notifySavedTogglesMarker() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try writeBundled("A", rel: "templates/CLAUDE.md", root: ctx.bundled)
        let file = node(rel: "templates/CLAUDE.md", root: ctx.bundled)

        try ctx.model.overrides.writeOverride("B", toRelative: "templates/CLAUDE.md")
        ctx.model.notifySaved(relativePath: "templates/CLAUDE.md")
        #expect(ctx.model.isOverridden(file))

        try ctx.model.overrides.writeOverride("A", toRelative: "templates/CLAUDE.md")
        ctx.model.notifySaved(relativePath: "templates/CLAUDE.md")
        #expect(!ctx.model.isOverridden(file))
    }

    @Test("Two-phase reset deletes the override and clears the marker")
    func resetRevertsToBundled() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try writeBundled("A", rel: "templates/CLAUDE.md", root: ctx.bundled)
        let file = node(rel: "templates/CLAUDE.md", root: ctx.bundled)
        try ctx.model.overrides.writeOverride("B", toRelative: "templates/CLAUDE.md")
        ctx.model.notifySaved(relativePath: "templates/CLAUDE.md")
        #expect(ctx.model.isOverridden(file))

        let reloadBefore = ctx.model.editorReloadToken
        ctx.model.resetToDefault(file)
        ctx.model.finishReset()  // the editor would call this after discarding its buffer

        #expect(!ctx.model.overrides.hasOverride(forRelative: "templates/CLAUDE.md"))
        #expect(!ctx.model.isOverridden(file))
        #expect(ctx.model.editorReloadToken == reloadBefore + 1)
    }

    @Test("Bundled-backed vs user-authored drives Reset vs Delete")
    func userAuthoredDetection() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try writeBundled("A", rel: "templates/CLAUDE.md", root: ctx.bundled)

        #expect(!ctx.model.isUserAuthored(node(rel: "templates/CLAUDE.md", root: ctx.bundled)))
        #expect(ctx.model.isUserAuthored(node(rel: "docs/notes.md", root: ctx.override)))
    }

    @Test("Delete removes a user-authored override")
    func deleteUserAuthored() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let file = node(rel: "docs/notes.md", root: ctx.override)
        try ctx.model.overrides.writeOverride("X", toRelative: "docs/notes.md")
        ctx.model.notifySaved(relativePath: "docs/notes.md")
        #expect(ctx.model.isOverridden(file))

        ctx.model.delete(file)
        #expect(!ctx.model.overrides.hasOverride(forRelative: "docs/notes.md"))
        #expect(!ctx.model.isOverridden(file))
    }

    // MARK: - Add

    @Test("Adding a doc writes the override, shows it in the tree, and selects it")
    func addDocAppearsSelected() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        // selection defaults to .base, where adds are allowed.
        let added = ctx.model.addUserFile(kind: .doc, rawName: "notes")

        let node = try #require(added)
        #expect(node.relativePath == "docs/notes.md")
        #expect(ctx.model.selectedFile == node)
        #expect(ctx.model.contentFiles.contains(node))
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/notes.md"))
        #expect(try ctx.model.overrides.string(atRelative: "docs/notes.md").hasPrefix("# notes"))
    }

    @Test("A colliding name suffix-walks instead of overwriting")
    func addCollisionSuffixWalks() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }

        let first = try #require(ctx.model.addUserFile(kind: .doc, rawName: "notes"))
        let second = try #require(ctx.model.addUserFile(kind: .doc, rawName: "notes"))

        #expect(first.relativePath == "docs/notes.md")
        #expect(second.relativePath == "docs/notes-1.md")
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/notes.md"))
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/notes-1.md"))
    }

    @Test("Adding a skill authors a SKILL.md folder")
    func addSkillFolder() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }

        let node = try #require(ctx.model.addUserFile(kind: .skill, rawName: "my-skill"))
        #expect(node.relativePath == "skills/my-skill/SKILL.md")
        #expect(ctx.model.overrides.hasOverride(forRelative: "skills/my-skill/SKILL.md"))
    }

    @Test("An invalid name is rejected and writes nothing")
    func addRejectsInvalidName() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }

        #expect(ctx.model.addUserFile(kind: .doc, rawName: "..") == nil)
        #expect(ctx.model.addUserFile(kind: .doc, rawName: "   ") == nil)
        // A slash collapses to a hyphen, so the name can never escape its folder.
        let slashy = try #require(ctx.model.addUserFile(kind: .doc, rawName: "a/b"))
        #expect(slashy.relativePath == "docs/a-b.md")
    }

    @Test("Add is offered only on Base, not templates or shared components")
    func addableKindsGating() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }

        ctx.model.selection = .base
        #expect(ctx.model.addableKinds == [.hook, .skill, .doc, .script, .agent])

        ctx.model.selection = .template("anything")
        #expect(ctx.model.addableKinds.isEmpty)

        ctx.model.selection = .sharedComponent("anything")
        #expect(ctx.model.addableKinds.isEmpty)
    }
}
