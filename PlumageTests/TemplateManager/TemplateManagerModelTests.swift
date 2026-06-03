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
}
