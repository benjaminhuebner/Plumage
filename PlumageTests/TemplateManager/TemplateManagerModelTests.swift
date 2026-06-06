import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManagerModel editing")
struct TemplateManagerModelTests {
    private func makeModel() throws -> (
        model: TemplateManagerModel, bundled: URL, override: URL, hookStore: URL, cleanup: () -> Void
    ) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = base.appending(path: "bundled", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        let hookStore = base.appending(path: "hook-wirings.json")
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: override, withIntermediateDirectories: true)
        let overrides = ScaffoldOverrides(bundledRoot: bundled, overrideRoot: override)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: nil), overrides: overrides,
            hookWiringStoreURL: hookStore)
        return (model, bundled, override, hookStore, { try? fm.removeItem(at: base) })
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

    @Test("Add is offered in every selection (Base, templates, shared components)")
    func addableKindsEverywhere() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let expected: [UserTemplateKind] = [.hook, .skill, .doc, .agent, .file, .folder]

        ctx.model.selection = .base
        #expect(ctx.model.addableKinds == expected)
        ctx.model.selection = .template("anything")
        #expect(ctx.model.addableKinds == expected)
        ctx.model.selection = .sharedComponent("anything")
        #expect(ctx.model.addableKinds == expected)
    }

    @Test("An arbitrary file name with separators is sanitized and stays contained")
    func arbitraryFileNameContained() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        // Selection defaults to Base with no folder selected → store root.
        let node = try #require(ctx.model.addUserFile(kind: .file, rawName: "../../escape.txt"))
        // Separators collapse to hyphens, so the name can never traverse out of the store.
        #expect(node.relativePath == "..-..-escape.txt")
        #expect(ctx.model.overrides.hasOverride(forRelative: node.relativePath))
    }

    // MARK: - Drag-and-drop import

    private func makeSourceTree() throws -> (root: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(
            path: "DropSrc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: root.appending(path: "hook.sh"), atomically: true, encoding: .utf8)
        try "# Note\n".write(to: root.appending(path: "note.md"), atomically: true, encoding: .utf8)
        try "ignore\n".write(to: root.appending(path: "bad.txt"), atomically: true, encoding: .utf8)
        let skill = root.appending(path: "myskill", directoryHint: .isDirectory)
        try fm.createDirectory(at: skill, withIntermediateDirectories: true)
        try "x\n".write(to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        return (root, { try? fm.removeItem(at: root) })
    }

    @Test("Drop imports any file (incl. unknown types) into the selected folder; skills route to skills/")
    func dropImportsAnyFileIntoSelectedFolder() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let src = try makeSourceTree()
        defer { src.cleanup() }
        try ctx.model.overrides.writeOverride("# Guide", toRelative: "docs/guide.md")
        ctx.model.selection = .base
        ctx.model.refreshContent()
        // Drop target = the selected .claude/docs folder.
        ctx.model.selectedFile = TemplateManagerModel.findNode(
            in: ctx.model.contentTree, relativePath: ".claude/docs")
        let urls = ["hook.sh", "note.md", "myskill", "bad.txt"].map { src.root.appending(path: $0) }

        let imported = ctx.model.importDropped(urls: urls)

        #expect(imported)
        // Everything lands in the selected folder — including the formerly-rejected .txt.
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/hook.sh"))
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/note.md"))
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/bad.txt"))
        // A skill folder is still special-cased into skills/.
        #expect(ctx.model.overrides.hasOverride(forRelative: "skills/myskill/SKILL.md"))
        // Copy semantics: the Finder source is untouched; nothing rejected.
        #expect(FileManager.default.fileExists(atPath: src.root.appending(path: "hook.sh").path))
        #expect(ctx.model.dropBanner == nil)
    }

    @Test("Dropping a .sh onto a Shared Component stores it under hooks/ and joins the component")
    func dropHookOntoComponentRoutesToHooks() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMDrop-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = base.appending(path: "bundled", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: override, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        // A real manifest URL so the membership join actually persists.
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: base.appending(path: "manifest.json")),
            overrides: ScaffoldOverrides(bundledRoot: bundled, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json"))
        let src = try makeSourceTree()
        defer { src.cleanup() }
        model.selection = .sharedComponent("swift-shared")
        model.refreshContent()

        _ = model.importDropped(urls: [src.root.appending(path: "hook.sh")])

        // The bytes land canonically under hooks/, not in the component's layer folder —
        // so a later scaffold (which copies from hooks/<name>.sh) resolves them.
        #expect(model.overrides.hasOverride(forRelative: "hooks/hook.sh"))
        #expect(!model.overrides.hasOverride(forRelative: "templates/swift-shared/hook.sh"))
        let component = try #require(model.catalog.sharedComponent(id: "swift-shared"))
        #expect(component.files(ofKind: .hook).contains("hook"))
    }

    @Test("A selected folder is retained across a content refresh")
    func folderSelectionRetained() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        _ = ctx.model.addUserFile(kind: .doc, rawName: "notes")  // materializes .claude/docs
        let folder = try #require(
            TemplateManagerModel.findNode(in: ctx.model.contentTree, relativePath: ".claude/docs"))
        ctx.model.selectedFile = folder

        ctx.model.refreshContent()

        #expect(ctx.model.selectedFile?.relativePath == ".claude/docs")
        #expect(ctx.model.selectedFile?.isDirectory == true)
    }

    @Test("A file added into a user-created root folder lands inside it and is shown")
    func fileAddedIntoRootFolderIsContained() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let folder = try #require(ctx.model.addUserFile(kind: .folder, rawName: "myfolder"))
        #expect(folder.relativePath == "myfolder")
        ctx.model.selectedFile = folder

        let file = try #require(ctx.model.addUserFile(kind: .file, rawName: "note.txt"))

        #expect(file.relativePath == "myfolder/note.txt")
        #expect(ctx.model.overrides.hasOverride(forRelative: "myfolder/note.txt"))
        #expect(
            TemplateManagerModel.findNode(in: ctx.model.contentTree, relativePath: "myfolder/note.txt") != nil)
    }

    @Test("Drop suffix-walks on collision in the target folder")
    func dropCollisionSuffixWalks() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let src = try makeSourceTree()
        defer { src.cleanup() }
        try ctx.model.overrides.writeOverride("existing", toRelative: "docs/note.md")
        ctx.model.selection = .base
        ctx.model.refreshContent()
        ctx.model.selectedFile = TemplateManagerModel.findNode(
            in: ctx.model.contentTree, relativePath: ".claude/docs")

        _ = ctx.model.importDropped(urls: [src.root.appending(path: "note.md")])

        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/note.md"))
        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/note-1.md"))
        #expect(try ctx.model.overrides.string(atRelative: "docs/note.md") == "existing")
    }

    // MARK: - Hook wiring

    @Test("Adding a hook raises the wiring sheet, persists, and scaffolds into settings.json")
    func hookWiringScaffolds() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }

        let node = try #require(ctx.model.addUserFile(kind: .hook, rawName: "my-hook"))
        #expect(node.relativePath == "hooks/my-hook.sh")
        // Adding a hook raises the wiring sheet and the hook reads as unwired.
        #expect(ctx.model.pendingHookWiring == node)
        #expect(ctx.model.needsWiring(node))

        ctx.model.saveWiring(forHook: node, event: .postToolUse, matcher: "Edit|Write")
        #expect(!ctx.model.needsWiring(node))

        let store = try HookWiringStore.load(from: ctx.hookStore)
        let withWiring = try SettingsComposer().settingsJSON(for: .macOS, userWirings: store.wirings)
        // JSONEncoder escapes "/" as "\/", so match the hook file name slash-agnostically.
        let json = String(decoding: withWiring, as: UTF8.self)
        #expect(json.contains("my-hook.sh"))
        #expect(json.contains("Edit|Write"))

        // Without the wiring the command is absent — proving the wiring drives it.
        let without = try SettingsComposer().settingsJSON(for: .macOS, userWirings: [])
        #expect(!String(decoding: without, as: UTF8.self).contains("my-hook.sh"))
    }

    @Test("Edit wiring updates the persisted event and matcher")
    func editWiring() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let node = try #require(ctx.model.addUserFile(kind: .hook, rawName: "my-hook"))

        ctx.model.saveWiring(forHook: node, event: .postToolUse, matcher: "Edit|Write")
        ctx.model.saveWiring(forHook: node, event: .userPromptSubmit, matcher: nil)

        let wiring = try #require(ctx.model.wiring(forHook: node))
        #expect(wiring.event == .userPromptSubmit)
        #expect(wiring.matcher == nil)
    }

    @Test("Deleting a hook removes its file and its wiring")
    func deleteHookRemovesWiring() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let node = try #require(ctx.model.addUserFile(kind: .hook, rawName: "my-hook"))
        ctx.model.saveWiring(forHook: node, event: .postToolUse, matcher: "Edit|Write")

        ctx.model.delete(node)

        #expect(!ctx.model.overrides.hasOverride(forRelative: "hooks/my-hook.sh"))
        let store = try HookWiringStore.load(from: ctx.hookStore)
        #expect(store.wiring(named: "my-hook") == nil)
    }

    // MARK: - Delete (trash + folder confirmation)

    @Test("Deleting a single file needs no confirmation and deletes immediately")
    func deleteSingleFileNoConfirmation() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let node = try #require(ctx.model.addUserFile(kind: .doc, rawName: "notes"))

        #expect(!ctx.model.requiresDeleteConfirmation(node))
        ctx.model.requestDelete(node)
        #expect(ctx.model.pendingDeleteConfirmation == nil)
        #expect(!ctx.model.overrides.hasOverride(forRelative: "docs/notes.md"))
    }

    @Test("Deleting a non-empty skill folder confirms, then trashes the whole tree")
    func deleteSkillFolderConfirms() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        let node = try #require(ctx.model.addUserFile(kind: .skill, rawName: "my-skill"))
        // A second file makes the skill directory non-empty beyond SKILL.md.
        try ctx.model.overrides.writeOverride("ref\n", toRelative: "skills/my-skill/reference.md")

        #expect(ctx.model.requiresDeleteConfirmation(node))
        ctx.model.requestDelete(node)
        // Not deleted yet — awaiting confirmation.
        #expect(ctx.model.pendingDeleteConfirmation == node)
        #expect(ctx.model.overrides.hasOverride(forRelative: "skills/my-skill/SKILL.md"))

        ctx.model.confirmPendingDelete()
        #expect(ctx.model.pendingDeleteConfirmation == nil)
        // The whole skill tree is gone, not just SKILL.md.
        #expect(!ctx.model.overrides.hasOverride(forRelative: "skills/my-skill/SKILL.md"))
        #expect(!ctx.model.overrides.hasOverride(forRelative: "skills/my-skill/reference.md"))
    }

    @Test("Delete is a no-op for a bundled-backed file (it resets instead)")
    func deleteIgnoresBundledBacked() throws {
        let ctx = try makeModel()
        defer { ctx.cleanup() }
        try writeBundled("A", rel: "templates/CLAUDE.md", root: ctx.bundled)
        try ctx.model.overrides.writeOverride("B", toRelative: "templates/CLAUDE.md")
        let node = node(rel: "templates/CLAUDE.md", root: ctx.bundled)

        ctx.model.requestDelete(node)
        #expect(ctx.model.pendingDeleteConfirmation == nil)
        // Still overridden — Delete does not touch a bundled-backed file.
        #expect(ctx.model.overrides.hasOverride(forRelative: "templates/CLAUDE.md"))
    }
}
