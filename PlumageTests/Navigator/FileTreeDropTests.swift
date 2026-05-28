import Foundation
import Testing

@testable import Plumage

@Suite("FileTreeDropResolver")
struct FileTreeDropTests {
    @Test("drop on folder row lands in that folder")
    func dropOnFolder() {
        let project = URL(filePath: "/tmp/proj")
        let folder = FileNode(
            url: URL(filePath: "/tmp/proj/.claude/docs"),
            relativePath: ".claude/docs",
            name: "docs",
            isDirectory: true,
            children: []
        )
        let target = FileTreeDropResolver.resolveDropTarget(for: folder, projectURL: project)
        #expect(target?.path == "/tmp/proj/.claude/docs")
    }

    @Test("drop on file inside the whitelist redirects to its parent")
    func dropOnFileRedirectsToParent() {
        let project = URL(filePath: "/tmp/proj")
        let file = FileNode(
            url: URL(filePath: "/tmp/proj/.claude/docs/intro.md"),
            relativePath: ".claude/docs/intro.md",
            name: "intro.md",
            isDirectory: false,
            children: nil
        )
        let target = FileTreeDropResolver.resolveDropTarget(for: file, projectURL: project)
        #expect(target?.path == "/tmp/proj/.claude/docs")
    }

    @Test("drop on a root-file row rejects (parent is project root)")
    func dropOnRootFileRejects() {
        let project = URL(filePath: "/tmp/proj")
        let rootFile = FileNode(
            url: URL(filePath: "/tmp/proj/.mcp.json"),
            relativePath: ".mcp.json",
            name: ".mcp.json",
            isDirectory: false,
            children: nil
        )
        #expect(FileTreeDropResolver.resolveDropTarget(for: rootFile, projectURL: project) == nil)
    }

    @Test("drop on a nested .claude folder is accepted")
    func dropOnNestedClaudeFolder() {
        let project = URL(filePath: "/tmp/proj")
        let agents = FileNode(
            url: URL(filePath: "/tmp/proj/.claude/agents"),
            relativePath: ".claude/agents",
            name: "agents",
            isDirectory: true,
            children: []
        )
        #expect(
            FileTreeDropResolver.resolveDropTarget(for: agents, projectURL: project)?.path
                == "/tmp/proj/.claude/agents")
    }

    @Test("drop on a .plumage folder rejects (not in the whitelist)")
    func dropOnPlumageRejects() {
        let project = URL(filePath: "/tmp/proj")
        let plumage = FileNode(
            url: URL(filePath: "/tmp/proj/.plumage"),
            relativePath: ".plumage",
            name: ".plumage",
            isDirectory: true,
            children: []
        )
        #expect(FileTreeDropResolver.resolveDropTarget(for: plumage, projectURL: project) == nil)
    }
}
