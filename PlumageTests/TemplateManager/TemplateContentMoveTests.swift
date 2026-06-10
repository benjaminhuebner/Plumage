import Foundation
import Testing

@testable import Plumage

// Internal move-drag in the content tree: user-authored files relocate physically in
// the override store; bundled files can't move in place, so they materialize at the
// target and tombstone the source. Restore Defaults lifts the tombstones.
@MainActor
@Suite("TemplateManager content-tree move and tombstones")
struct TemplateContentMoveTests {
    private func makeModel() -> (model: TemplateManagerModel, override: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMMove-\(UUID().uuidString)", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try? fm.createDirectory(at: override, withIntermediateDirectories: true)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: base.appending(path: "manifest.json")),
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json"))
        return (model, override, { try? fm.removeItem(at: base) })
    }

    private func find(_ nodes: [FileNode], _ path: [String]) -> FileNode? {
        guard let head = path.first, let node = nodes.first(where: { $0.name == head }) else { return nil }
        return path.count == 1 ? node : find(node.children ?? [], Array(path.dropFirst()))
    }

    @Test("moving a user-authored file between two folders remaps its path and keeps selection")
    func userAuthoredMoveRemaps() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        // Two user-created folders at the project root (typeless adds land relative to
        // the selection, so clear it first), and a file inside the first.
        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "alpha")
        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "beta")
        let alpha = try #require(find(ctx.model.contentTree, ["alpha"]))
        ctx.model.selectedFile = alpha
        let created = try #require(ctx.model.addUserFile(kind: .file, rawName: "note"))
        let source = created.relativePath
        #expect(source.hasPrefix("alpha/"))

        let beta = try #require(find(ctx.model.contentTree, ["beta"]))
        ctx.model.moveNodes([created], into: beta)

        let leaf = (source as NSString).lastPathComponent
        let newPath = "beta/\(leaf)"
        #expect(FileManager.default.fileExists(atPath: ctx.override.appending(path: newPath).path))
        #expect(!FileManager.default.fileExists(atPath: ctx.override.appending(path: source).path))
        #expect(find(ctx.model.contentTree, ["beta", leaf]) != nil)
        #expect(ctx.model.selectedFile?.relativePath == newPath)
    }

    @Test("moving a user file to the tree root (background drop) lands at the scope root")
    func moveToScopeRoot() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "alpha")
        let alpha = try #require(find(ctx.model.contentTree, ["alpha"]))
        ctx.model.selectedFile = alpha
        let created = try #require(ctx.model.addUserFile(kind: .file, rawName: "loose"))
        #expect(created.relativePath.hasPrefix("alpha/"))

        ctx.model.moveNodes([created], intoStoreDir: ctx.model.activeScope.storageRoot)

        let leaf = (created.relativePath as NSString).lastPathComponent
        #expect(FileManager.default.fileExists(atPath: ctx.override.appending(path: leaf).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: ctx.override.appending(path: created.relativePath).path))
        #expect(find(ctx.model.contentTree, [leaf]) != nil)
    }

    @Test("a dragged leaf's payload URL maps back to its content node")
    func dragPayloadURLMapsToNode() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        // A bundled leaf resolves to the bundled URL until an override exists —
        // the drag payload must still map back to the same tree node.
        let leaves = TemplateManagerModel.flattenLeaves(ctx.model.contentTree)
        let bundled = try #require(leaves.first { !ctx.model.isUserAuthored($0) })
        let payload = FileTreeDragPayload(url: bundled.url)
        let mapped = try #require(ctx.model.contentNode(forURL: payload.url))
        #expect(mapped.relativePath == bundled.relativePath)
    }

    @Test("moving a user file into a folder within a template scope keeps it in scope (#00078)")
    func moveWithinTemplateScope() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()

        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "box")
        ctx.model.selectedFile = nil
        let file = try #require(ctx.model.addUserFile(kind: .file, rawName: "bla.md"))
        #expect(file.relativePath == "templates/macOS/bla.md")  // scoped store path
        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "templates/macOS/bla.md").path))

        let box = try #require(find(ctx.model.contentTree, ["box"]))
        ctx.model.moveNodes([file], into: box)

        // The file stays inside the template's scope and is still visible — not leaked to Base.
        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "templates/macOS/box/bla.md").path))
        #expect(
            !FileManager.default.fileExists(atPath: ctx.override.appending(path: "box/bla.md").path))
        #expect(find(ctx.model.contentTree, ["box", "bla.md"]) != nil)
        #expect(ctx.model.selectedFile?.relativePath == "templates/macOS/box/bla.md")
    }

    @Test("moving a user file into a folder within a component scope keeps it in scope (#00078)")
    func moveWithinComponentScope() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "box")
        ctx.model.selectedFile = nil
        let file = try #require(ctx.model.addUserFile(kind: .file, rawName: "bla.md"))
        let box = try #require(find(ctx.model.contentTree, ["box"]))
        ctx.model.moveNodes([file], into: box)

        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "components/swift-shared/box/bla.md").path))
        #expect(find(ctx.model.contentTree, ["box", "bla.md"]) != nil)
    }

    @Test("a base-root loose file dropped onto .claude relocates under .claude and stays visible (#00084)")
    func looseFileMovesIntoClaudeRoot() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        // A user-authored loose file at the store root (the project root in the tree).
        ctx.model.selectedFile = nil
        let file = try #require(ctx.model.addUserFile(kind: .file, rawName: "bla.md"))
        #expect(file.relativePath == "bla.md")

        let claude = try #require(find(ctx.model.contentTree, [".claude"]))
        ctx.model.moveNodes([file], into: claude)

        // Bug 1 + 2 fixed: the file lives under `.claude/` in the store, shows in the
        // `.claude` subtree, and no longer sits at the store root.
        #expect(FileManager.default.fileExists(atPath: ctx.override.appending(path: ".claude/bla.md").path))
        #expect(!FileManager.default.fileExists(atPath: ctx.override.appending(path: "bla.md").path))
        #expect(find(ctx.model.contentTree, [".claude", "bla.md"]) != nil)
        #expect(ctx.model.selectedFile?.relativePath == ".claude/bla.md")
    }

    @Test("moving a user folder into another folder relocates its whole subtree")
    func userFolderMoveRelocates() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()
        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "src")
        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "dst")
        ctx.model.selectedFile = find(ctx.model.contentTree, ["src"])
        _ = ctx.model.addUserFile(kind: .file, rawName: "f.txt")  // src/f.txt

        let src = try #require(find(ctx.model.contentTree, ["src"]))
        let dst = try #require(find(ctx.model.contentTree, ["dst"]))
        ctx.model.moveNodes([src], into: dst)

        #expect(
            FileManager.default.fileExists(atPath: ctx.override.appending(path: "dst/src/f.txt").path))
        #expect(!FileManager.default.fileExists(atPath: ctx.override.appending(path: "src").path))
        #expect(find(ctx.model.contentTree, ["dst", "src"]) != nil)
    }

    @Test("deleting a user folder is offered and trashes the whole folder")
    func userFolderDelete() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()
        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "trashme")
        ctx.model.selectedFile = find(ctx.model.contentTree, ["trashme"])
        _ = ctx.model.addUserFile(kind: .file, rawName: "x.txt")

        let folder = try #require(find(ctx.model.contentTree, ["trashme"]))
        #expect(ctx.model.isUserAuthored(folder))  // a user folder is deletable
        ctx.model.requestDelete(folder)
        if ctx.model.pendingDeleteConfirmation != nil { ctx.model.confirmPendingDelete() }

        #expect(!FileManager.default.fileExists(atPath: ctx.override.appending(path: "trashme").path))
        #expect(find(ctx.model.contentTree, ["trashme"]) == nil)
    }

    @Test("Renaming a user file relocates the override (extension preserved) and re-selects it")
    func renameUserFile() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()
        ctx.model.selectedFile = nil
        let node = try #require(ctx.model.addUserFile(kind: .doc, rawName: "old"))  // docs/old.md

        ctx.model.beginRenameContent(node)
        ctx.model.contentRename?.name = "new"  // stem only → keeps .md
        ctx.model.commitContentRename()

        #expect(ctx.model.overrides.hasOverride(forRelative: "docs/new.md"))
        #expect(!ctx.model.overrides.hasOverride(forRelative: "docs/old.md"))
        #expect(ctx.model.selectedFile?.relativePath == "docs/new.md")
        #expect(ctx.model.contentRename == nil)
    }

    @Test("Renaming a user folder relocates the whole folder")
    func renameUserFolder() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()
        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "box")
        let box = try #require(find(ctx.model.contentTree, ["box"]))

        ctx.model.beginRenameContent(box)
        ctx.model.contentRename?.name = "crate"
        ctx.model.commitContentRename()

        #expect(FileManager.default.fileExists(atPath: ctx.override.appending(path: "crate").path))
        #expect(!FileManager.default.fileExists(atPath: ctx.override.appending(path: "box").path))
        #expect(find(ctx.model.contentTree, ["crate"]) != nil)
    }

    @Test("A bundled-backed row cannot be renamed")
    func renameRejectsBundled() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()
        let bundled = try #require(
            find(ctx.model.contentTree, [".claude", "hooks", "block-git-commit.sh"]))
        ctx.model.beginRenameContent(bundled)
        #expect(ctx.model.contentRename == nil)  // not user-authored → no rename session
    }

    @Test("moving a user hook out of hooks/ drops its wiring")
    func userHookMoveDropsWiring() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let hook = try #require(ctx.model.addUserFile(kind: .hook, rawName: "myhook"))
        ctx.model.saveWiring(forHook: hook, event: .preToolUse, matcher: "Edit")
        #expect(ctx.model.hookWirings.wiring(named: "myhook") != nil)

        let docs = try #require(find(ctx.model.contentTree, [".claude", "docs"]))
        ctx.model.moveNodes([hook], into: docs)

        #expect(ctx.model.hookWirings.wiring(named: "myhook") == nil)
    }

    @Test("moving a bundled file suppresses the source and materializes it at the target")
    func bundledMoveSuppressesAndMaterializes() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let bundled = try #require(
            find(ctx.model.contentTree, [".claude", "hooks", "block-git-commit.sh"]))
        #expect(!ctx.model.isUserAuthored(bundled))  // genuinely bundled, not an override

        let docs = try #require(find(ctx.model.contentTree, [".claude", "docs"]))
        ctx.model.moveNodes([bundled], into: docs)

        #expect(find(ctx.model.contentTree, [".claude", "hooks", "block-git-commit.sh"]) == nil)
        #expect(find(ctx.model.contentTree, [".claude", "docs", "block-git-commit.sh"]) != nil)
        #expect(ctx.model.overrides.isSuppressed(relativePath: "hooks/block-git-commit.sh"))
        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "docs/block-git-commit.sh").path))
    }

    @Test("Restore Defaults lifts file tombstones so the bundled original reappears")
    func restoreLiftsTombstone() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()
        let bundled = try #require(
            find(ctx.model.contentTree, [".claude", "hooks", "block-git-commit.sh"]))
        let docs = try #require(find(ctx.model.contentTree, [".claude", "docs"]))
        ctx.model.moveNodes([bundled], into: docs)
        #expect(ctx.model.overrides.isSuppressed(relativePath: "hooks/block-git-commit.sh"))

        ctx.model.restoreAllDefaults()

        #expect(!ctx.model.overrides.isSuppressed(relativePath: "hooks/block-git-commit.sh"))
        #expect(find(ctx.model.contentTree, [".claude", "hooks", "block-git-commit.sh"]) != nil)
    }
}
