import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeProjectFiles.moveItem")
struct ClaudeProjectFilesMoveTests {
    @Test("moveItem moves a file between folders")
    func moveFile() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let docs = root.appendingPathComponent(".claude/docs", isDirectory: true)
        let agents = root.appendingPathComponent(".claude/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let source = docs.appendingPathComponent("foo.md")
        try "x".write(to: source, atomically: true, encoding: .utf8)

        let moved = try ClaudeProjectFiles.moveItem(at: source, to: agents)

        #expect(moved.path == agents.appendingPathComponent("foo.md").path)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test("moveItem moves a folder between folders")
    func moveFolder() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let parent = root.appendingPathComponent(".claude", isDirectory: true)
        let target = root.appendingPathComponent(".plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let team = parent.appendingPathComponent("agents/team", isDirectory: true)
        try FileManager.default.createDirectory(at: team, withIntermediateDirectories: true)
        try "x".write(to: team.appendingPathComponent("lead.md"), atomically: true, encoding: .utf8)

        let moved = try ClaudeProjectFiles.moveItem(at: team, to: target)

        #expect(moved.path == target.appendingPathComponent("team").path)
        #expect(!FileManager.default.fileExists(atPath: team.path))
        #expect(
            FileManager.default.fileExists(
                atPath: target.appendingPathComponent("team/lead.md").path))
    }

    @Test("moveItem rejects moving a folder into its own subtree")
    func rejectSelfSubtree() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let agents = root.appendingPathComponent(".claude/agents", isDirectory: true)
        let team = agents.appendingPathComponent("team", isDirectory: true)
        try FileManager.default.createDirectory(at: team, withIntermediateDirectories: true)

        #expect(throws: CocoaError.self) {
            _ = try ClaudeProjectFiles.moveItem(at: agents, to: team)
        }
        #expect(FileManager.default.fileExists(atPath: agents.path))
    }

    @Test("moveItem suffix-walks on name collision")
    func suffixWalkOnCollision() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let docs = root.appendingPathComponent(".claude/docs", isDirectory: true)
        let agents = root.appendingPathComponent(".claude/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try "from-docs".write(
            to: docs.appendingPathComponent("dup.md"), atomically: true, encoding: .utf8)
        try "already-there".write(
            to: agents.appendingPathComponent("dup.md"), atomically: true, encoding: .utf8)

        let moved = try ClaudeProjectFiles.moveItem(
            at: docs.appendingPathComponent("dup.md"), to: agents)

        #expect(moved.path == agents.appendingPathComponent("dup-1.md").path)
        let collidingContent = try String(
            contentsOf: agents.appendingPathComponent("dup.md"), encoding: .utf8)
        #expect(collidingContent == "already-there")
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageMoveItem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
