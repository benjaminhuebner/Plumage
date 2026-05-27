import Foundation
import Testing

@testable import Plumage

struct FileTreeBuilderTests {
    @Test
    func emptyProjectReturnsEmptyArray() throws {
        let project = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: project) }

        let nodes = FileTreeBuilder.build(projectURL: project)
        #expect(nodes.isEmpty)
    }

    @Test
    func treeShape() throws {
        let project = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: project) }

        let fm = FileManager.default
        try fm.createDirectory(
            at: project.appendingPathComponent(".claude/docs"),
            withIntermediateDirectories: true)
        try "hello".write(
            to: project.appendingPathComponent(".claude/docs/foo.md"),
            atomically: true, encoding: .utf8)
        try fm.createDirectory(
            at: project.appendingPathComponent(".claude/agents/team"),
            withIntermediateDirectories: true)
        try "lead".write(
            to: project.appendingPathComponent(".claude/agents/team/lead.md"),
            atomically: true, encoding: .utf8)
        try fm.createDirectory(
            at: project.appendingPathComponent(".plumage"),
            withIntermediateDirectories: true)

        let nodes = FileTreeBuilder.build(projectURL: project)

        #expect(nodes.count == 2)
        let names = nodes.map(\.name)
        #expect(names == [".claude", ".plumage"])

        let claude = try #require(nodes.first { $0.name == ".claude" })
        #expect(claude.isDirectory)
        let claudeChildren = try #require(claude.children)
        // Folders first (agents, docs), alphabetical.
        #expect(claudeChildren.map(\.name) == ["agents", "docs"])

        let agents = try #require(claudeChildren.first { $0.name == "agents" })
        let agentsChildren = try #require(agents.children)
        #expect(agentsChildren.map(\.name) == ["team"])

        let team = try #require(agentsChildren.first)
        let teamChildren = try #require(team.children)
        #expect(teamChildren.map(\.name) == ["lead.md"])
        let lead = try #require(teamChildren.first)
        #expect(!lead.isDirectory)
        #expect(lead.relativePath == ".claude/agents/team/lead.md")
        #expect(lead.children == nil)
    }

    @Test
    func skipsHiddenSystemFiles() throws {
        let project = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: project) }

        let fm = FileManager.default
        try fm.createDirectory(
            at: project.appendingPathComponent(".claude"),
            withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent(".claude/.DS_Store"))
        try Data().write(to: project.appendingPathComponent(".claude/Icon\r"))
        try "real".write(
            to: project.appendingPathComponent(".claude/keep.md"),
            atomically: true, encoding: .utf8)

        let nodes = FileTreeBuilder.build(projectURL: project)
        let claude = try #require(nodes.first)
        let children = try #require(claude.children)
        #expect(children.map(\.name) == ["keep.md"])
    }

    @Test
    func rootIsWhitelistOnly() throws {
        let project = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: project) }

        let fm = FileManager.default
        // Whitelisted root file.
        try "{}".write(
            to: project.appendingPathComponent(".mcp.json"),
            atomically: true, encoding: .utf8)
        // NOT-whitelisted: regular project source folder and a git dir.
        try fm.createDirectory(
            at: project.appendingPathComponent("Plumage"),
            withIntermediateDirectories: true)
        try fm.createDirectory(
            at: project.appendingPathComponent(".git"),
            withIntermediateDirectories: true)
        // A root markdown that is NOT whitelisted.
        try "no".write(
            to: project.appendingPathComponent("README.md"),
            atomically: true, encoding: .utf8)
        // A whitelist member that we don't create — must be absent from output.
        // (no CLAUDE.md, no CLAUDE.local.md)

        let nodes = FileTreeBuilder.build(projectURL: project)
        #expect(nodes.map(\.name) == [".mcp.json"])
    }

    @Test
    func skipsSymlinks() throws {
        let project = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: project) }

        let fm = FileManager.default
        try fm.createDirectory(
            at: project.appendingPathComponent(".claude/skills"),
            withIntermediateDirectories: true)
        // Real target outside the tree.
        let externalDir = project.appendingPathComponent("external-skill", isDirectory: true)
        try fm.createDirectory(at: externalDir, withIntermediateDirectories: true)
        try "x".write(
            to: externalDir.appendingPathComponent("inside.md"),
            atomically: true, encoding: .utf8)
        // Symlink inside the watched tree pointing at the external dir.
        let link = project.appendingPathComponent(".claude/skills/linked")
        try fm.createSymbolicLink(at: link, withDestinationURL: externalDir)
        // A regular sibling we expect to see.
        try "y".write(
            to: project.appendingPathComponent(".claude/skills/real.md"),
            atomically: true, encoding: .utf8)

        let nodes = FileTreeBuilder.build(projectURL: project)
        let claude = try #require(nodes.first)
        let skillsNode = try #require(claude.children?.first { $0.name == "skills" })
        let skillsChildren = try #require(skillsNode.children)
        #expect(skillsChildren.map(\.name) == ["real.md"])
    }
}
