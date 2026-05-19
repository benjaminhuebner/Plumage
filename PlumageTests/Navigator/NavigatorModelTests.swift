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
