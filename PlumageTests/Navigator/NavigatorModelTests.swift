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
