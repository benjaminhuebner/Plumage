import Foundation
import Testing

@testable import Plumage

@Suite("NavigatorModel")
@MainActor
struct NavigatorModelTests {
    @Test("reload populates rootNodes from FileTreeBuilder")
    func reloadPopulatesRootNodes() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/PROJECT.md", content: "p")
        // .plumage exists on disk but is intentionally hidden from the tree.
        try fixture.makeFile(at: ".plumage/config.json", content: "{}")
        try fixture.makeFile(at: ".mcp.json", content: "{}")

        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        #expect(model.rootNodes.map(\.name) == [".claude", ".mcp.json"])
    }

    @Test("reload publishes empty-context paths for target files only")
    func reloadPublishesEmptyContextPaths() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/CLAUDE.md", content: "")
        try fixture.makeFile(at: ".claude/docs/PROJECT.md", content: "  \n\t\n")
        // Non-target empty file and a filled target must stay out of the set.
        try fixture.makeFile(at: ".claude/docs/notes.md", content: "")
        try fixture.makeFile(at: "CLAUDE.md", content: "# Real")

        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        #expect(
            model.emptyContextFilePaths == [".claude/CLAUDE.md", ".claude/docs/PROJECT.md"])
        // Every ancestor folder of an empty target warns on collapse.
        #expect(model.foldersHidingEmptyContextFile == [".claude", ".claude/docs"])

        // Filling a target removes it from both sets on the next reload.
        try fixture.makeFile(at: ".claude/CLAUDE.md", content: "# Now real")
        await model.reload(projectURL: fixture.root)
        #expect(model.emptyContextFilePaths == [".claude/docs/PROJECT.md"])
        #expect(model.foldersHidingEmptyContextFile == [".claude", ".claude/docs"])
    }

    @Test("collectFoldersHidingEmptyContextPaths returns every ancestor folder")
    func collectFoldersHidingEmptyContextPaths() {
        #expect(
            NavigatorModel.collectFoldersHidingEmptyContextPaths(
                [".claude/docs/PROJECT.md", ".claude/CLAUDE.md"])
                == [".claude", ".claude/docs"])
        // A root-level target file has no ancestor folder to warn.
        #expect(
            NavigatorModel.collectFoldersHidingEmptyContextPaths(["CLAUDE.md"]).isEmpty)
        #expect(NavigatorModel.collectFoldersHidingEmptyContextPaths([]).isEmpty)
    }

    @Test("beginPendingCreate seeds the default name for files and folders")
    func beginPendingCreateSeedsName() async throws {
        let fixture = try NavigatorModelFixture()
        let parent = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        let model = NavigatorModel()

        model.beginPendingCreate(parent: parent, isFolder: false)
        #expect(model.pendingCreate?.name == "untitled.md")

        model.beginPendingCreate(parent: parent, isFolder: true)
        #expect(model.pendingCreate?.name == "untitled")
    }

    @Test("commitPendingCreate writes a file and returns its projectFile route")
    func commitPendingCreateFile() async throws {
        let fixture = try NavigatorModelFixture()
        let parent = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        let model = NavigatorModel()

        model.beginPendingCreate(parent: parent, isFolder: false)
        model.pendingCreate?.name = "intro.md"
        let route = await model.commitPendingCreate(projectURL: fixture.root)

        #expect(route == .projectFile(relativePath: ".claude/docs/intro.md"))
        #expect(model.pendingCreate == nil)
        #expect(
            FileManager.default.fileExists(
                atPath: parent.appendingPathComponent("intro.md").path))
    }

    @Test("commitPendingCreate on a folder returns nil (folder is not a selectable route)")
    func commitPendingCreateFolder() async throws {
        let fixture = try NavigatorModelFixture()
        let parent = fixture.root.appendingPathComponent(".claude", isDirectory: true)
        let model = NavigatorModel()

        model.beginPendingCreate(parent: parent, isFolder: true)
        model.pendingCreate?.name = "research"
        let route = await model.commitPendingCreate(projectURL: fixture.root)

        #expect(route == nil)
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(
            atPath: parent.appendingPathComponent("research").path, isDirectory: &isDir)
        #expect(isDir.boolValue)
    }

    @Test("commitPendingCreate with empty name is a no-op")
    func commitPendingCreateEmpty() async throws {
        let fixture = try NavigatorModelFixture()
        let parent = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        let model = NavigatorModel()
        model.beginPendingCreate(parent: parent, isFolder: false)
        model.pendingCreate?.name = "   "
        let route = await model.commitPendingCreate(projectURL: fixture.root)
        #expect(route == nil)
        #expect(model.pendingCreate != nil)
    }

    @Test("commitRename returns a projectFile route under the new path")
    func commitRenameReturnsProjectFile() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let source = fixture.root.appendingPathComponent(".claude/docs/foo.md")
        let model = NavigatorModel()

        model.beginRename(url: source)
        model.renaming?.name = "bar.md"
        let route = await model.commitRename(projectURL: fixture.root)

        #expect(route == .projectFile(relativePath: ".claude/docs/bar.md"))
    }

    @Test("handleFinderDrop copies a file into a whitelisted folder")
    func handleFinderDropCopies() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/.keep", content: "")
        let source = try fixture.makeExternal(name: "extra.md", content: "x")
        let model = NavigatorModel()

        let target = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        await model.handleFinderDrop(
            urls: [source], targetFolder: target, projectURL: fixture.root)

        let landed = target.appendingPathComponent("extra.md")
        #expect(FileManager.default.fileExists(atPath: landed.path))
        #expect(model.dropRejectMessage == nil)
    }

    @Test("handleFinderDrop rejects drops outside the whitelist")
    func handleFinderDropRejectsNonWhitelisted() async throws {
        let fixture = try NavigatorModelFixture()
        let source = try fixture.makeExternal(name: "x.md", content: "x")
        let model = NavigatorModel(bannerDisplayDuration: .milliseconds(50))
        let outside = fixture.root.appendingPathComponent("Plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        await model.handleFinderDrop(
            urls: [source], targetFolder: outside, projectURL: fixture.root)

        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("x.md").path))
        #expect(model.dropRejectMessage == "Drop target outside managed area")
    }

    @Test("handleInternalMove moves files between whitelist folders")
    func handleInternalMoveBetweenFolders() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        try fixture.makeFile(at: ".claude/agents/.keep", content: "")
        let model = NavigatorModel()

        let source = fixture.root.appendingPathComponent(".claude/docs/foo.md")
        let target = fixture.root.appendingPathComponent(".claude/agents", isDirectory: true)
        await model.handleInternalMove(
            sources: [source], targetFolder: target, projectURL: fixture.root)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(
            FileManager.default.fileExists(
                atPath: target.appendingPathComponent("foo.md").path))
    }

    @Test("handleInternalMove rejects moving a folder into its own subtree")
    func handleInternalMoveRejectsSelfSubtree() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/agents/team/lead.md", content: "x")
        let model = NavigatorModel(bannerDisplayDuration: .milliseconds(50))

        let source = fixture.root.appendingPathComponent(".claude/agents", isDirectory: true)
        let target = fixture.root.appendingPathComponent(".claude/agents/team", isDirectory: true)
        await model.handleInternalMove(
            sources: [source], targetFolder: target, projectURL: fixture.root)

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(model.dropRejectMessage == "Cannot move folder into its own subfolder")
    }

    @Test("handleFinderDrop into the source's own folder is a no-op, no duplicate")
    func handleFinderDropSameFolderIsNoop() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/note.md", content: "x")
        let model = NavigatorModel()

        let folder = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        let source = folder.appendingPathComponent("note.md")
        await model.handleFinderDrop(
            urls: [source], targetFolder: folder, projectURL: fixture.root)

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("note-1.md").path))
    }

    @Test("commitRename emits a .moved route rewrite")
    func commitRenameEmitsMovedRewrite() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let model = NavigatorModel()

        model.beginRename(url: fixture.root.appendingPathComponent(".claude/docs/foo.md"))
        model.renaming?.name = "bar.md"
        _ = await model.commitRename(projectURL: fixture.root)

        #expect(
            model.routeRewrites == [
                .moved(
                    oldRelativePath: ".claude/docs/foo.md",
                    newRelativePath: ".claude/docs/bar.md")
            ])
    }

    @Test("trash emits a .removed route rewrite")
    func trashEmitsRemovedRewrite() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/gone.md", content: "x")
        let model = NavigatorModel()

        await model.trash(
            url: fixture.root.appendingPathComponent(".claude/docs/gone.md"),
            projectURL: fixture.root)

        #expect(model.routeRewrites == [.removed(oldRelativePath: ".claude/docs/gone.md")])
    }

    @Test("handleInternalMove emits a .moved rewrite per source")
    func handleInternalMoveEmitsMovedRewrites() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        try fixture.makeFile(at: ".claude/agents/.keep", content: "")
        let model = NavigatorModel()

        let source = fixture.root.appendingPathComponent(".claude/docs/foo.md")
        let target = fixture.root.appendingPathComponent(".claude/agents", isDirectory: true)
        await model.handleInternalMove(
            sources: [source], targetFolder: target, projectURL: fixture.root)

        #expect(
            model.routeRewrites == [
                .moved(
                    oldRelativePath: ".claude/docs/foo.md",
                    newRelativePath: ".claude/agents/foo.md")
            ])
    }

    // MARK: External-change detection (inode diff)

    @Test("first reload sets a baseline and emits no externalRewrites")
    func reloadFirstSetsBaseline() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let model = NavigatorModel()

        await model.reload(projectURL: fixture.root)

        #expect(model.externalRewrites.isEmpty)
    }

    @Test("reload follows an external rename via inode → externalRewrites .moved")
    func reloadDetectsExternalRename() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        // Rename outside the model — the OS preserves the inode.
        try FileManager.default.moveItem(
            at: fixture.root.appendingPathComponent(".claude/docs/foo.md"),
            to: fixture.root.appendingPathComponent(".claude/docs/bar.md"))
        await model.reload(projectURL: fixture.root)

        #expect(
            model.externalRewrites == [
                .moved(
                    oldRelativePath: ".claude/docs/foo.md",
                    newRelativePath: ".claude/docs/bar.md")
            ])
    }

    @Test("reload follows an external move across folders")
    func reloadDetectsExternalMove() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        try fixture.makeFile(at: ".claude/agents/.keep", content: "")
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        try FileManager.default.moveItem(
            at: fixture.root.appendingPathComponent(".claude/docs/foo.md"),
            to: fixture.root.appendingPathComponent(".claude/agents/foo.md"))
        await model.reload(projectURL: fixture.root)

        #expect(
            model.externalRewrites == [
                .moved(
                    oldRelativePath: ".claude/docs/foo.md",
                    newRelativePath: ".claude/agents/foo.md")
            ])
    }

    @Test("reload detects an external delete → externalRewrites .removed")
    func reloadDetectsExternalDelete() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        try FileManager.default.removeItem(
            at: fixture.root.appendingPathComponent(".claude/docs/foo.md"))
        await model.reload(projectURL: fixture.root)

        #expect(model.externalRewrites == [.removed(oldRelativePath: ".claude/docs/foo.md")])
    }

    @Test("reload with no change emits no externalRewrites")
    func reloadNoChangeNoRewrites() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)
        await model.reload(projectURL: fixture.root)
        #expect(model.externalRewrites.isEmpty)
    }

    @Test("reload ignores a newly added file (no rewrite)")
    func reloadNewFileNoRewrite() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)
        try fixture.makeFile(at: ".claude/docs/bar.md", content: "y")
        await model.reload(projectURL: fixture.root)
        #expect(model.externalRewrites.isEmpty)
    }

    @Test("switching to a different project resets the baseline (no spurious removals)")
    func reloadProjectSwitchResetsBaseline() async throws {
        let fixtureA = try NavigatorModelFixture()
        try fixtureA.makeFile(at: ".claude/docs/a.md", content: "x")
        let fixtureB = try NavigatorModelFixture()
        try fixtureB.makeFile(at: ".claude/docs/b.md", content: "y")
        let model = NavigatorModel()

        await model.reload(projectURL: fixtureA.root)
        await model.reload(projectURL: fixtureB.root)

        // A's files are absent from B, but that's a project switch, not a delete.
        #expect(model.externalRewrites.isEmpty)
    }

    // MARK: deriveExternalRewrites (pure)

    @Test("deriveExternalRewrites: empty baseline yields nothing")
    func deriveFirstLoad() {
        #expect(
            NavigatorModel.deriveExternalRewrites(
                previousInodes: [:], currentInodes: ["a.md": 1], currentPaths: ["a.md"]
            ).isEmpty)
    }

    @Test("deriveExternalRewrites: folder rename emits one sorted .moved per file")
    func deriveFolderRename() {
        let rewrites = NavigatorModel.deriveExternalRewrites(
            previousInodes: ["d/a.md": 1, "d/b.md": 2],
            currentInodes: ["e/a.md": 1, "e/b.md": 2],
            currentPaths: ["e/a.md", "e/b.md"])
        #expect(
            rewrites == [
                .moved(oldRelativePath: "d/a.md", newRelativePath: "e/a.md"),
                .moved(oldRelativePath: "d/b.md", newRelativePath: "e/b.md"),
            ])
    }

    @Test("deriveExternalRewrites: a gone path with no inode match is .removed")
    func deriveRemoved() {
        let rewrites = NavigatorModel.deriveExternalRewrites(
            previousInodes: ["a.md": 1], currentInodes: [:], currentPaths: [])
        #expect(rewrites == [.removed(oldRelativePath: "a.md")])
    }

    @Test("deriveExternalRewrites: an in-place edit (same path) is not a rewrite")
    func deriveInPlaceEdit() {
        // Atomic save can swap the inode while keeping the path — must not drop.
        let rewrites = NavigatorModel.deriveExternalRewrites(
            previousInodes: ["a.md": 1], currentInodes: ["a.md": 9], currentPaths: ["a.md"])
        #expect(rewrites.isEmpty)
    }

    @Test("deriveExternalRewrites: inode reuse pairs delete+create as a move (known trade-off)")
    func deriveInodeReuse() {
        let rewrites = NavigatorModel.deriveExternalRewrites(
            previousInodes: ["a.md": 1], currentInodes: ["c.md": 1], currentPaths: ["c.md"])
        #expect(rewrites == [.moved(oldRelativePath: "a.md", newRelativePath: "c.md")])
    }
}

private final class NavigatorModelFixture {
    let root: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageNavigatorModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.root = tmp
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeFile(at relativePath: String, content: String) throws {
        let url = root.appendingPathComponent(relativePath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func makeExternal(name: String, content: String) throws -> URL {
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageExternal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let url = external.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
