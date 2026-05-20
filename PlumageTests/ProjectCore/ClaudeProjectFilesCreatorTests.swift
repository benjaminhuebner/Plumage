import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeProjectFiles creators")
struct ClaudeProjectFilesCreatorTests {
    @Test("createDoc writes .md at .claude/docs/<name>")
    func createDocHappyPath() throws {
        let fixture = try CreatorFixture()
        let url = try ClaudeProjectFiles.createDoc(
            name: "intro.md", projectURL: fixture.root)
        #expect(url.lastPathComponent == "intro.md")
        #expect(url.path.contains("/.claude/docs/"))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("createDoc normalizes missing extension to .md")
    func createDocNormalizesExtension() throws {
        let fixture = try CreatorFixture()
        let url = try ClaudeProjectFiles.createDoc(
            name: "untitled", projectURL: fixture.root)
        #expect(url.lastPathComponent == "untitled.md")
    }

    @Test("createDoc treats unknown extension as part of the stem and appends .md")
    func createDocAppendsMDOnUnknownExt() throws {
        let fixture = try CreatorFixture()
        let url = try ClaudeProjectFiles.createDoc(
            name: "notes.txt", projectURL: fixture.root)
        #expect(url.lastPathComponent == "notes.txt.md")
    }

    @Test("createDoc suffixes on collision: foo.md, foo-1.md, foo-2.md")
    func createDocSuffixOnCollision() throws {
        let fixture = try CreatorFixture()
        let first = try ClaudeProjectFiles.createDoc(
            name: "foo.md", projectURL: fixture.root)
        let second = try ClaudeProjectFiles.createDoc(
            name: "foo.md", projectURL: fixture.root)
        let third = try ClaudeProjectFiles.createDoc(
            name: "foo.md", projectURL: fixture.root)
        #expect(first.lastPathComponent == "foo.md")
        #expect(second.lastPathComponent == "foo-1.md")
        #expect(third.lastPathComponent == "foo-2.md")
    }

    @Test("createClaudeMarkdown writes at .claude/<name>")
    func createClaudeMarkdownHappyPath() throws {
        let fixture = try CreatorFixture()
        let url = try ClaudeProjectFiles.createClaudeMarkdown(
            name: "PROJECT.md", projectURL: fixture.root)
        #expect(url.lastPathComponent == "PROJECT.md")
        // Must live directly in `.claude/`, not `.claude/docs/`.
        #expect(url.deletingLastPathComponent().lastPathComponent == ".claude")
    }

    @Test("createClaudeMarkdown rejects CLAUDE.md reserved name")
    func createClaudeMarkdownReservedName() throws {
        let fixture = try CreatorFixture()
        #expect(throws: ClaudeProjectFilesError.reservedName("CLAUDE.md")) {
            _ = try ClaudeProjectFiles.createClaudeMarkdown(
                name: "CLAUDE.md", projectURL: fixture.root)
        }
    }

    @Test("createHookFile writes .sh shebang for default extension")
    func createHookFileShellShebang() throws {
        let fixture = try CreatorFixture()
        let url = try ClaudeProjectFiles.createHookFile(
            name: "lint", projectURL: fixture.root)
        #expect(url.lastPathComponent == "lint.sh")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.hasPrefix("#!/usr/bin/env bash"))
    }

    @Test("createHookFile writes python shebang when extension is .py")
    func createHookFilePythonShebang() throws {
        let fixture = try CreatorFixture()
        let url = try ClaudeProjectFiles.createHookFile(
            name: "process.py", projectURL: fixture.root)
        #expect(url.lastPathComponent == "process.py")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.hasPrefix("#!/usr/bin/env python3"))
    }

    @Test("createHookFolder creates a folder under .claude/hooks/")
    func createHookFolderHappyPath() throws {
        let fixture = try CreatorFixture()
        let url = try ClaudeProjectFiles.createHookFolder(
            name: "pre-tool-use", projectURL: fixture.root)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
        #expect(url.deletingLastPathComponent().lastPathComponent == "hooks")
    }

    @Test("createHookFolder suffixes on collision")
    func createHookFolderSuffix() throws {
        let fixture = try CreatorFixture()
        let first = try ClaudeProjectFiles.createHookFolder(
            name: "scripts", projectURL: fixture.root)
        let second = try ClaudeProjectFiles.createHookFolder(
            name: "scripts", projectURL: fixture.root)
        #expect(first.lastPathComponent == "scripts")
        #expect(second.lastPathComponent == "scripts-1")
    }

    @Test("createSkill writes skill folder with SKILL.md frontmatter stub")
    func createSkillHappyPath() throws {
        let fixture = try CreatorFixture()
        let folderURL = try ClaudeProjectFiles.createSkill(
            name: "my-skill", projectURL: fixture.root)
        #expect(folderURL.lastPathComponent == "my-skill")
        let skillMD = folderURL.appendingPathComponent("SKILL.md")
        let content = try String(contentsOf: skillMD, encoding: .utf8)
        #expect(content.contains("name: my-skill"))
        #expect(content.contains("description:"))
        #expect(content.contains("# my-skill"))
    }

    @Test("createSkill suffixes on collision; SKILL.md frontmatter uses the suffixed name")
    func createSkillSuffix() throws {
        let fixture = try CreatorFixture()
        let first = try ClaudeProjectFiles.createSkill(
            name: "tasks", projectURL: fixture.root)
        let second = try ClaudeProjectFiles.createSkill(
            name: "tasks", projectURL: fixture.root)
        #expect(first.lastPathComponent == "tasks")
        #expect(second.lastPathComponent == "tasks-1")
        let secondMD = try String(
            contentsOf: second.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(secondMD.contains("name: tasks-1"))
    }

    @Test("createSkillFolder creates a sub-folder under the given skill at relativePath")
    func createSkillFolderNested() throws {
        let fixture = try CreatorFixture()
        _ = try ClaudeProjectFiles.createSkill(name: "alpha", projectURL: fixture.root)
        let refs = try ClaudeProjectFiles.createSkillFolder(
            name: "references", underSkill: "alpha", relativePath: "",
            projectURL: fixture.root)
        #expect(refs.lastPathComponent == "references")
        #expect(refs.path.contains("/skills/alpha/references"))

        let deeper = try ClaudeProjectFiles.createSkillFolder(
            name: "api-v2", underSkill: "alpha", relativePath: "references",
            projectURL: fixture.root)
        #expect(deeper.lastPathComponent == "api-v2")
        #expect(deeper.path.contains("/skills/alpha/references/api-v2"))
    }

    @Test("createSkillFile creates files with default content based on extension")
    func createSkillFileShebangs() throws {
        let fixture = try CreatorFixture()
        _ = try ClaudeProjectFiles.createSkill(name: "beta", projectURL: fixture.root)
        let runner = try ClaudeProjectFiles.createSkillFile(
            name: "run.sh", underSkill: "beta", relativePath: "",
            projectURL: fixture.root)
        let runnerContent = try String(contentsOf: runner, encoding: .utf8)
        #expect(runnerContent.hasPrefix("#!/usr/bin/env bash"))

        let pyRunner = try ClaudeProjectFiles.createSkillFile(
            name: "extract.py", underSkill: "beta", relativePath: "",
            projectURL: fixture.root)
        let pyContent = try String(contentsOf: pyRunner, encoding: .utf8)
        #expect(pyContent.hasPrefix("#!/usr/bin/env python3"))

        let md = try ClaudeProjectFiles.createSkillFile(
            name: "notes.md", underSkill: "beta", relativePath: "",
            projectURL: fixture.root)
        let mdContent = try String(contentsOf: md, encoding: .utf8)
        #expect(mdContent.isEmpty)
    }

    @Test("findFreeName returns the original name when the slot is empty")
    func findFreeNameEmptySlot() throws {
        let fixture = try CreatorFixture()
        let target = try fixture.makeDirectory(at: ".claude/docs")
        let free = try ClaudeProjectFiles.findFreeName(in: target, base: "intro.md")
        #expect(free.lastPathComponent == "intro.md")
    }

    @Test("findFreeName suffixes through occupied slots until free")
    func findFreeNameSuffixWalk() throws {
        let fixture = try CreatorFixture()
        let target = try fixture.makeDirectory(at: ".claude/docs")
        try "a".write(
            to: target.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        try "b".write(
            to: target.appendingPathComponent("note-1.md"), atomically: true, encoding: .utf8)
        let free = try ClaudeProjectFiles.findFreeName(in: target, base: "note.md")
        #expect(free.lastPathComponent == "note-2.md")
    }

    @Test("findFreeName works for extensionless folder names")
    func findFreeNameFolder() throws {
        let fixture = try CreatorFixture()
        let target = try fixture.makeDirectory(at: ".claude/skills")
        try FileManager.default.createDirectory(
            at: target.appendingPathComponent("alpha"), withIntermediateDirectories: true)
        let free = try ClaudeProjectFiles.findFreeName(in: target, base: "alpha")
        #expect(free.lastPathComponent == "alpha-1")
    }

    @Test("enumerateHooks lists both .sh and .py files at top level")
    func enumerateHooksAcceptsShAndPy() throws {
        let fixture = try CreatorFixture()
        try fixture.makeFile(at: ".claude/hooks/a.sh", content: "#!/bin/sh")
        try fixture.makeFile(at: ".claude/hooks/b.py", content: "#!/usr/bin/env python3")
        try fixture.makeFile(at: ".claude/hooks/skip.txt", content: "no")
        let urls = try ClaudeProjectFiles.enumerateHooks(projectURL: fixture.root)
        let names = urls.map(\.lastPathComponent).sorted()
        #expect(names == ["a.sh", "b.py"])
    }

    @Test(
        "normalizedFileName edge cases",
        arguments: [
            // (raw, allowed, fallback, expected)
            ("", ["md"], "md", "untitled.md"),
            ("   ", ["md"], "md", "untitled.md"),
            ("  intro.md  ", ["md"], "md", "intro.md"),
            ("notes.txt", ["md"], "md", "notes.txt.md"),
            ("my.docs.md", ["md"], "md", "my.docs.md"),
            ("lint", ["sh", "py"], "sh", "lint.sh"),
            ("run.py", ["sh", "py"], "sh", "run.py"),
            ("FOO.MD", ["md"], "md", "FOO.md"),
        ]
    )
    func normalizedFileNameEdges(
        raw: String, allowed: [String], fallback: String, expected: String
    ) {
        #expect(
            ClaudeProjectFiles.normalizedFileName(
                raw, allowedExtensions: allowed, fallback: fallback)
                == expected)
    }

    @Test("enumerateClaudeMarkdown lists *.md at .claude/ root excluding CLAUDE.md")
    func enumerateClaudeMarkdownExcludesReserved() throws {
        let fixture = try CreatorFixture()
        try fixture.makeFile(at: ".claude/CLAUDE.md", content: "bootstrap")
        try fixture.makeFile(at: ".claude/PROJECT.md", content: "project")
        try fixture.makeFile(at: ".claude/notes.md", content: "notes")
        try fixture.makeFile(at: ".claude/ignore.txt", content: "skip")
        try fixture.makeFile(at: ".claude/docs/foo.md", content: "nested")
        let listed = try ClaudeProjectFiles.enumerateClaudeMarkdown(projectURL: fixture.root)
        let names = listed.map { $0.lastPathComponent }
        #expect(names == ["notes.md", "PROJECT.md"])
    }
}

private final class CreatorFixture {
    let root: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PlumageCreator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.root = tmp
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func makeDirectory(at relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeFile(at relativePath: String, content: String) throws {
        let url = root.appendingPathComponent(relativePath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
