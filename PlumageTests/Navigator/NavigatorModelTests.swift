import Foundation
import Testing

@testable import Plumage

@Suite("NavigatorModel")
@MainActor
struct NavigatorModelTests {
    @Test("reload populates docs, hooks, and skills from disk")
    func reloadPopulatesAll() async throws {
        let fixture = try NavigatorModelFixture()
        try fixture.makeFile(at: ".claude/docs/PROJECT.md", content: "p")
        try fixture.makeFile(at: ".claude/docs/notes.md", content: "n")
        try fixture.makeFile(at: ".claude/hooks/lint.sh", content: "#!/bin/sh")
        try fixture.makeFile(at: ".claude/skills/alpha/SKILL.md", content: "alpha")

        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        #expect(model.docs.map { $0.lastPathComponent } == ["notes.md", "PROJECT.md"])
        #expect(model.hooks.map { $0.lastPathComponent } == ["lint.sh"])
        #expect(model.skills.count == 1)
        #expect(model.loadError == nil)
    }

    @Test("reload returns empty collections when no .claude/ folders exist")
    func reloadEmptyProject() async throws {
        let fixture = try NavigatorModelFixture()
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)
        #expect(model.docs.isEmpty)
        #expect(model.hooks.isEmpty)
        #expect(model.skills.isEmpty)
        #expect(model.loadError == nil)
    }

    @Test("beginPendingCreate seeds the default name for each section")
    func beginPendingCreateSeedsName() async throws {
        let model = NavigatorModel()
        model.beginPendingCreate(.docs)
        #expect(model.pendingCreate?.section == .docs)
        #expect(model.pendingCreate?.name == "untitled.md")

        model.beginPendingCreate(.hookFile)
        #expect(model.pendingCreate?.name == "untitled.sh")
        model.beginPendingCreate(.skill)
        #expect(model.pendingCreate?.name == "untitled-skill")
    }

    @Test("cancelPendingCreate clears the inline row without disk effects")
    func cancelPendingCreate() async throws {
        let fixture = try NavigatorModelFixture()
        let model = NavigatorModel()
        model.beginPendingCreate(.docs)
        model.cancelPendingCreate()
        #expect(model.pendingCreate == nil)
        // No file landed on disk.
        let docs = try ClaudeProjectFiles.enumerateDocs(projectURL: fixture.root)
        #expect(docs.isEmpty)
    }

    @Test("commitPendingCreate on .docs writes the file and selects the new route")
    func commitPendingCreateDoc() async throws {
        let fixture = try NavigatorModelFixture()
        let model = NavigatorModel()
        model.beginPendingCreate(.docs)
        model.pendingCreate?.name = "intro.md"
        let route = await model.commitPendingCreate(projectURL: fixture.root)
        #expect(route == .doc(relativePath: ".claude/docs/intro.md"))
        #expect(model.pendingCreate == nil)
        #expect(model.docs.map(\.lastPathComponent) == ["intro.md"])
        #expect(model.lastCreatedRoute == .doc(relativePath: ".claude/docs/intro.md"))
    }

    @Test("commitPendingCreate on .hookFile uses createHookFile and lands in hooks list")
    func commitPendingCreateHook() async throws {
        let fixture = try NavigatorModelFixture()
        let model = NavigatorModel()
        model.beginPendingCreate(.hookFile)
        model.pendingCreate?.name = "lint"
        let route = await model.commitPendingCreate(projectURL: fixture.root)
        #expect(route == .hook(name: "lint.sh"))
        #expect(model.hooks.map(\.lastPathComponent) == ["lint.sh"])
    }

    @Test("commitPendingCreate with empty name is a no-op (textfield stays focused)")
    func commitPendingCreateEmpty() async throws {
        let fixture = try NavigatorModelFixture()
        let model = NavigatorModel()
        model.beginPendingCreate(.docs)
        model.pendingCreate?.name = "   "
        let route = await model.commitPendingCreate(projectURL: fixture.root)
        #expect(route == nil)
        #expect(model.pendingCreate != nil)
    }

    @Test("commitPendingCreate on reserved CLAUDE.md surfaces a banner and keeps pending row")
    func commitPendingCreateReservedClaudeMD() async throws {
        let fixture = try NavigatorModelFixture()
        let model = NavigatorModel(bannerDisplayDuration: .milliseconds(50))
        model.beginPendingCreate(.claudeMarkdown)
        model.pendingCreate?.name = "CLAUDE.md"
        let route = await model.commitPendingCreate(projectURL: fixture.root)
        #expect(route == nil)
        #expect(model.dropRejectMessage != nil)
        #expect(model.pendingCreate != nil)
    }

    @Test("showBanner sets message and auto-clears after duration")
    func showBannerAutoClears() async throws {
        let model = NavigatorModel(bannerDisplayDuration: .milliseconds(80))
        model.showBanner("Only .md files allowed in Docs")
        #expect(model.dropRejectMessage == "Only .md files allowed in Docs")
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.dropRejectMessage == nil)
    }

    @Test("clearBanner cancels the auto-dismiss timer")
    func clearBannerCancels() async throws {
        let model = NavigatorModel(bannerDisplayDuration: .seconds(60))
        model.showBanner("hi")
        #expect(model.dropRejectMessage == "hi")
        model.clearBanner()
        #expect(model.dropRejectMessage == nil)
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
}
