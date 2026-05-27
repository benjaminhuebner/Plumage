import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeProjectFiles")
struct ClaudeProjectFilesTests {
    @Test("claudeMDURL points at .claude/CLAUDE.md under project root")
    func claudeMDURLPoints() throws {
        let fixture = try ClaudeFilesFixture()
        let url = ClaudeProjectFiles.claudeMDURL(projectURL: fixture.root)
        #expect(url.path.hasSuffix(".claude/CLAUDE.md"))
        #expect(url.deletingLastPathComponent().lastPathComponent == ".claude")
    }

    @Test("claudeLocalMDURL points at .claude/CLAUDE.local.md")
    func claudeLocalMDURLPoints() throws {
        let fixture = try ClaudeFilesFixture()
        let url = ClaudeProjectFiles.claudeLocalMDURL(projectURL: fixture.root)
        #expect(url.path.hasSuffix(".claude/CLAUDE.local.md"))
        #expect(url.deletingLastPathComponent().lastPathComponent == ".claude")
    }

    @Test("mcpJSONURL points at project-root .mcp.json (not under .claude/)")
    func mcpJSONURLPoints() throws {
        let fixture = try ClaudeFilesFixture()
        let url = ClaudeProjectFiles.mcpJSONURL(projectURL: fixture.root)
        #expect(url.lastPathComponent == ".mcp.json")
        #expect(
            url.deletingLastPathComponent().standardizedFileURL.path
                == fixture.root.standardizedFileURL.path)
    }

    @Test("createFileAt writes an empty file with the typed name")
    func createFileAtWritesFile() throws {
        let fixture = try ClaudeFilesFixture()
        let target = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        let url = try ClaudeProjectFiles.createFileAt(parent: target, name: "intro.md")
        #expect(url.path.hasSuffix(".claude/docs/intro.md"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        #expect(data.isEmpty)
    }

    @Test("createFileAt suffix-walks on collision")
    func createFileAtSuffixWalks() throws {
        let fixture = try ClaudeFilesFixture()
        let target = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        let first = try ClaudeProjectFiles.createFileAt(parent: target, name: "intro.md")
        let second = try ClaudeProjectFiles.createFileAt(parent: target, name: "intro.md")
        #expect(first.lastPathComponent == "intro.md")
        #expect(second.lastPathComponent == "intro-1.md")
    }

    @Test("createFolderAt creates the directory and suffix-walks on collision")
    func createFolderAtCreates() throws {
        let fixture = try ClaudeFilesFixture()
        let target = fixture.root.appendingPathComponent(".claude", isDirectory: true)
        let first = try ClaudeProjectFiles.createFolderAt(parent: target, name: "agents")
        let second = try ClaudeProjectFiles.createFolderAt(parent: target, name: "agents")
        #expect(first.lastPathComponent == "agents")
        #expect(second.lastPathComponent == "agents-1")
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
        #expect(isDir.boolValue)
    }

    @Test("renameFile preserves the original extension when the new name has no extension")
    func renameFilePreservesExtension() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let source = fixture.root.appendingPathComponent(".claude/docs/foo.md")

        let renamed = try ClaudeProjectFiles.renameFile(at: source, to: "bar")

        #expect(renamed.lastPathComponent == "bar.md")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test("renameFile keeps the typed extension when explicit")
    func renameFileKeepsExplicitExtension() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "x")
        let source = fixture.root.appendingPathComponent(".claude/docs/foo.md")

        let renamed = try ClaudeProjectFiles.renameFile(at: source, to: "bar.txt")

        #expect(renamed.lastPathComponent == "bar.txt")
    }
}

private final class ClaudeFilesFixture {
    let root: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageClaudeFiles-\(UUID().uuidString)", isDirectory: true)
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
