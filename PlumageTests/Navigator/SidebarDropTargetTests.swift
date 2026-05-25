import Foundation
import Testing

@testable import Plumage

@Suite("SidebarDropTarget drop validation + copy semantics")
struct SidebarDropTargetTests {
    @Test("Docs accepts .md, rejects other extensions")
    func docsAcceptsMD() throws {
        let fixture = try DropFixture()
        let source = try fixture.sourceFile(name: "intro.md")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source], section: .docs, projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        #expect(outcome.rejected.isEmpty)
        let expected = fixture.root.appendingPathComponent(".claude/docs/intro.md")
        #expect(outcome.accepted.first?.standardizedFileURL.path == expected.standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: expected.path))
        // Source remains in place (Copy semantics).
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Docs rejects .txt with reject message")
    func docsRejectsTxt() throws {
        let fixture = try DropFixture()
        let source = try fixture.sourceFile(name: "notes.txt")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source], section: .docs, projectURL: fixture.root)
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.rejected == [source])
        let banner = SidebarDropTarget.bannerMessage(outcome: outcome, section: .docs)
        #expect(banner == "Only .md files allowed in Docs")
    }

    @Test("Mixed accept/reject bannered as 'N of M files skipped'")
    func multiFileMixedOutcome() throws {
        let fixture = try DropFixture()
        let good = try fixture.sourceFile(name: "intro.md")
        let bad1 = try fixture.sourceFile(name: "skip1.txt")
        let bad2 = try fixture.sourceFile(name: "skip2.csv")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [good, bad1, bad2], section: .docs, projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        #expect(outcome.rejected.count == 2)
        let banner = SidebarDropTarget.bannerMessage(outcome: outcome, section: .docs)
        #expect(banner == "2 of 3 files skipped — Only .md files allowed in Docs")
    }

    @Test("Name collisions in Docs apply foo, foo-1, foo-2 suffix walk")
    func collisionSuffixWalk() throws {
        let fixture = try DropFixture()
        let docs = fixture.root.appendingPathComponent(".claude/docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "existing".write(
            to: docs.appendingPathComponent("intro.md"),
            atomically: true, encoding: .utf8)
        let source = try fixture.sourceFile(name: "intro.md", content: "new")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source], section: .docs, projectURL: fixture.root)
        #expect(outcome.accepted.first?.lastPathComponent == "intro-1.md")
    }

    @Test("Hooks accepts .sh files")
    func hooksAcceptsShell() throws {
        let fixture = try DropFixture()
        let source = try fixture.sourceFile(name: "lint.sh")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source], section: .hooks, projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
    }

    @Test("Hooks accepts folder drops with recursive copy")
    func hooksAcceptsFolders() throws {
        let fixture = try DropFixture()
        let sourceFolder = fixture.sources.appendingPathComponent("custom", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try "#!/bin/sh".write(
            to: sourceFolder.appendingPathComponent("inner.sh"),
            atomically: true, encoding: .utf8)
        let outcome = try SidebarDropTarget.performDrop(
            sources: [sourceFolder], section: .hooks, projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        let copied = fixture.root
            .appendingPathComponent(".claude/hooks/custom/inner.sh")
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }

    @Test("Docs rejects folder drops")
    func docsRejectsFolders() throws {
        let fixture = try DropFixture()
        let sourceFolder = fixture.sources.appendingPathComponent("foo", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let outcome = try SidebarDropTarget.performDrop(
            sources: [sourceFolder], section: .docs, projectURL: fixture.root)
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.rejected == [sourceFolder])
    }

    @Test("Claude markdown section accepts .md, rejects .txt")
    func claudeMarkdownAcceptsMD() throws {
        let fixture = try DropFixture()
        let md = try fixture.sourceFile(name: "PROJECT.md")
        let txt = try fixture.sourceFile(name: "skip.txt")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [md, txt], section: .claudeMarkdown, projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        #expect(outcome.rejected == [txt])
        let target = fixture.root.appendingPathComponent(".claude/PROJECT.md")
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test("Claude markdown rejects folder drops")
    func claudeMarkdownRejectsFolders() throws {
        let fixture = try DropFixture()
        let folder = fixture.sources.appendingPathComponent("nope", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outcome = try SidebarDropTarget.performDrop(
            sources: [folder], section: .claudeMarkdown, projectURL: fixture.root)
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.rejected == [folder])
    }

    @Test("hookSub routes drops into the nested hook folder")
    func hookSubNestedTarget() throws {
        let fixture = try DropFixture()
        let source = try fixture.sourceFile(name: "lint.sh")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source], section: .hookSub(relativePath: "shared"),
            projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        let target = fixture.root.appendingPathComponent(".claude/hooks/shared/lint.sh")
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test("skillSub routes drops into the nested skill subdirectory")
    func skillSubNestedTarget() throws {
        let fixture = try DropFixture()
        let source = try fixture.sourceFile(name: "notes.md")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source],
            section: .skillSub(skillName: "alpha", relativePath: "refs"),
            projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        let target = fixture.root.appendingPathComponent(".claude/skills/alpha/refs/notes.md")
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test("resolveSection returns the last section whose minY is at or above y")
    func resolveSectionPicksLastAboveTarget() {
        let anchors: [SidebarDropTarget.Section: CGFloat] = [
            .docs: 100,
            .claudeMarkdown: 200,
            .hooks: 300,
            .skillsTopLevel: 400,
        ]
        #expect(SidebarDropTarget.resolveSection(at: 50, anchors: anchors) == nil)
        #expect(SidebarDropTarget.resolveSection(at: 150, anchors: anchors) == .docs)
        #expect(SidebarDropTarget.resolveSection(at: 250, anchors: anchors) == .claudeMarkdown)
        #expect(SidebarDropTarget.resolveSection(at: 350, anchors: anchors) == .hooks)
        #expect(SidebarDropTarget.resolveSection(at: 500, anchors: anchors) == .skillsTopLevel)
        // Exact anchor sits ON the header — that section wins.
        #expect(SidebarDropTarget.resolveSection(at: 100, anchors: anchors) == .docs)
    }

    @Test("resolveSection returns nil for an empty anchor dict")
    func resolveSectionEmpty() {
        #expect(SidebarDropTarget.resolveSection(at: 100, anchors: [:]) == nil)
    }

    @Test(
        "Managed drop accepts the type's default extension",
        arguments: ManagedFileType.allCases
    )
    func managedSectionAcceptsDefaultExtension(type: ManagedFileType) throws {
        let fixture = try DropFixture()
        let source = try fixture.sourceFile(name: "alpha.\(type.defaultExtension)")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source], section: .managed(type: type), projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        #expect(outcome.rejected.isEmpty)
        let dst = fixture.root
            .appendingPathComponent(type.relativePath)
            .appendingPathComponent("alpha.\(type.defaultExtension)")
        #expect(FileManager.default.fileExists(atPath: dst.path))
    }

    @Test(
        "Managed drop rejects unsupported extensions with the type's rejection message",
        arguments: ManagedFileType.allCases
    )
    func managedSectionRejectsUnknownExtensions(type: ManagedFileType) throws {
        let fixture = try DropFixture()
        let bogus = try fixture.sourceFile(name: "skip.bogus")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [bogus], section: .managed(type: type), projectURL: fixture.root)
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.rejected == [bogus])
        let banner = SidebarDropTarget.bannerMessage(outcome: outcome, section: .managed(type: type))
        #expect(banner == type.rejectionMessage)
    }

    @Test("Agents section accepts folder drops (recursive type)")
    func agentsAcceptsFolderDrops() throws {
        let fixture = try DropFixture()
        let sourceFolder = fixture.sources.appendingPathComponent("team", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try "x".write(
            to: sourceFolder.appendingPathComponent("lead.md"),
            atomically: true, encoding: .utf8)
        let outcome = try SidebarDropTarget.performDrop(
            sources: [sourceFolder], section: .managed(type: .agents),
            projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        let nested = fixture.root.appendingPathComponent(".claude/agents/team/lead.md")
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test("Output Styles section rejects folder drops (not recursive)")
    func outputStylesRejectsFolderDrops() throws {
        let fixture = try DropFixture()
        let folder = fixture.sources.appendingPathComponent("nope", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outcome = try SidebarDropTarget.performDrop(
            sources: [folder], section: .managed(type: .outputStyles),
            projectURL: fixture.root)
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.rejected == [folder])
    }

    @Test("Skills top-level: file drop is wrapped into an implicit skill folder")
    func skillsTopLevelFileImpliesSkill() throws {
        let fixture = try DropFixture()
        let source = try fixture.sourceFile(name: "tasks.md")
        let outcome = try SidebarDropTarget.performDrop(
            sources: [source], section: .skillsTopLevel, projectURL: fixture.root)
        #expect(outcome.accepted.count == 1)
        let skillFolder = fixture.root.appendingPathComponent(".claude/skills/tasks", isDirectory: true)
        var isDir: ObjCBool = false
        #expect(
            FileManager.default.fileExists(atPath: skillFolder.path, isDirectory: &isDir)
                && isDir.boolValue)
        let copy = skillFolder.appendingPathComponent("tasks.md")
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }
}

private final class DropFixture {
    let root: URL
    let sources: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageSidebarDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.root = tmp
        self.sources = tmp.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func sourceFile(name: String, content: String = "hi") throws -> URL {
        let url = sources.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
