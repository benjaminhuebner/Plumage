import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeProjectFiles")
struct ClaudeProjectFilesTests {
    @Test("enumerateDocs returns *.md sorted, ignores non-markdown")
    func enumerateDocsHappyPath() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/docs/PROJECT.md", content: "project")
        try fixture.makeFile(at: ".claude/docs/decisions.md", content: "decisions")
        try fixture.makeFile(at: ".claude/docs/architecture.md", content: "arch")
        try fixture.makeFile(at: ".claude/docs/notes.md", content: "notes")
        try fixture.makeFile(at: ".claude/docs/ignore.txt", content: "skip me")

        let docs = try ClaudeProjectFiles.enumerateDocs(projectURL: fixture.root)

        let names = docs.map { $0.lastPathComponent }
        #expect(names == ["architecture.md", "decisions.md", "notes.md", "PROJECT.md"])
    }

    @Test("enumerateDocs returns empty array when folder is absent")
    func enumerateDocsMissingFolder() throws {
        let fixture = try ClaudeFilesFixture()

        let docs = try ClaudeProjectFiles.enumerateDocs(projectURL: fixture.root)

        #expect(docs.isEmpty)
    }

    @Test("enumerateDocs returns empty array when folder is empty")
    func enumerateDocsEmptyFolder() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeDirectory(at: ".claude/docs")

        let docs = try ClaudeProjectFiles.enumerateDocs(projectURL: fixture.root)

        #expect(docs.isEmpty)
    }

    @Test("enumerateHooks returns *.sh sorted, ignores non-shell files")
    func enumerateHooksHappyPath() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/hooks/lint-swift.sh", content: "#!/bin/sh")
        try fixture.makeFile(at: ".claude/hooks/block-git-commit.sh", content: "#!/bin/sh")
        try fixture.makeFile(at: ".claude/hooks/format-swift.sh", content: "#!/bin/sh")
        try fixture.makeFile(at: ".claude/hooks/README.md", content: "ignored")

        let hooks = try ClaudeProjectFiles.enumerateHooks(projectURL: fixture.root)

        let names = hooks.map { $0.lastPathComponent }
        #expect(names == ["block-git-commit.sh", "format-swift.sh", "lint-swift.sh"])
    }

    @Test("enumerateHooks returns empty array when folder is absent")
    func enumerateHooksMissingFolder() throws {
        let fixture = try ClaudeFilesFixture()

        let hooks = try ClaudeProjectFiles.enumerateHooks(projectURL: fixture.root)

        #expect(hooks.isEmpty)
    }

    @Test("enumerateSkills returns nested tree per skill folder")
    func enumerateSkillsRecursive() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/skills/alpha/SKILL.md", content: "alpha skill")
        try fixture.makeFile(at: ".claude/skills/alpha/references/api.md", content: "ref")
        try fixture.makeFile(at: ".claude/skills/alpha/scripts/run.sh", content: "#!/bin/sh")
        try fixture.makeFile(at: ".claude/skills/beta/SKILL.md", content: "beta skill")

        let tree = try ClaudeProjectFiles.enumerateSkills(projectURL: fixture.root)

        #expect(tree.count == 2)
        guard case .folder(let alphaName, let alphaChildren) = tree[0] else {
            Issue.record("first node should be a folder, got \(tree[0])")
            return
        }
        #expect(alphaName == "alpha")
        // Folders sort before files: [references/, scripts/, SKILL.md].
        #expect(alphaChildren.count == 3)
        guard case .folder(let refsName, let refsChildren) = alphaChildren[0] else {
            Issue.record("expected references folder")
            return
        }
        #expect(refsName == "references")
        #expect(refsChildren.count == 1)
        if case .file(let url) = refsChildren[0] {
            #expect(url.lastPathComponent == "api.md")
        } else {
            Issue.record("expected file under references")
        }
        guard case .folder(let scriptsName, _) = alphaChildren[1] else {
            Issue.record("expected scripts folder")
            return
        }
        #expect(scriptsName == "scripts")
        if case .file(let url) = alphaChildren[2] {
            #expect(url.lastPathComponent == "SKILL.md")
        } else {
            Issue.record("expected SKILL.md file at top of alpha")
        }

        guard case .folder(let betaName, let betaChildren) = tree[1] else {
            Issue.record("second node should be a folder")
            return
        }
        #expect(betaName == "beta")
        #expect(betaChildren.count == 1)
    }

    @Test("enumerateSkills returns empty when folder absent")
    func enumerateSkillsMissingFolder() throws {
        let fixture = try ClaudeFilesFixture()

        let tree = try ClaudeProjectFiles.enumerateSkills(projectURL: fixture.root)

        #expect(tree.isEmpty)
    }

    @Test("claudeMDURL points at .claude/CLAUDE.md under project root")
    func claudeMDURLPoints() throws {
        let fixture = try ClaudeFilesFixture()
        let url = ClaudeProjectFiles.claudeMDURL(projectURL: fixture.root)
        #expect(url.path.hasSuffix(".claude/CLAUDE.md"))
        #expect(url.deletingLastPathComponent().lastPathComponent == ".claude")
    }

    @Test("settingsURL builds path for each settings file")
    func settingsURLForAllCases() throws {
        let fixture = try ClaudeFilesFixture()
        let main = ClaudeProjectFiles.settingsURL(projectURL: fixture.root, file: .main)
        let local = ClaudeProjectFiles.settingsURL(projectURL: fixture.root, file: .local)
        #expect(main.lastPathComponent == "settings.json")
        #expect(local.lastPathComponent == "settings.local.json")
        #expect(main.deletingLastPathComponent().lastPathComponent == ".claude")
        #expect(local.deletingLastPathComponent().lastPathComponent == ".claude")
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

    func makeDirectory(at relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func makeFile(at relativePath: String, content: String) throws {
        let url = root.appendingPathComponent(relativePath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
