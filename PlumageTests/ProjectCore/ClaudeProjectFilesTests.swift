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
        // Sits directly under the project root, NOT under .claude/.
        #expect(
            url.deletingLastPathComponent().standardizedFileURL.path
                == fixture.root.standardizedFileURL.path)
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

    // MARK: - Generic enumerate/create over ManagedFileType.allCases

    @Test(
        "enumerate returns empty for an absent folder per type",
        arguments: ManagedFileType.allCases
    )
    func enumerateMissingFolderPerType(type: ManagedFileType) throws {
        let fixture = try ClaudeFilesFixture()
        let urls = try ClaudeProjectFiles.enumerate(type, projectURL: fixture.root)
        #expect(urls.isEmpty)
    }

    @Test(
        "create writes a file with the type's default extension at the correct path",
        arguments: ManagedFileType.allCases
    )
    func createWritesAtCorrectPath(type: ManagedFileType) throws {
        let fixture = try ClaudeFilesFixture()
        let url = try ClaudeProjectFiles.create(type, name: "untitled", projectURL: fixture.root)
        let expectedExt = type.defaultExtension
        #expect(url.pathExtension == expectedExt)
        #expect(FileManager.default.fileExists(atPath: url.path))
        // File sits under `<projectURL>/<type.relativePath>/...`.
        let basePath = fixture.root
            .appendingPathComponent(type.relativePath, isDirectory: true)
            .standardizedFileURL.path
        #expect(url.standardizedFileURL.path.hasPrefix(basePath + "/"))
    }

    @Test(
        "enumerate picks up files created via create() for each type",
        arguments: ManagedFileType.allCases
    )
    func enumerateAfterCreateRoundTrip(type: ManagedFileType) throws {
        let fixture = try ClaudeFilesFixture()
        let created = try ClaudeProjectFiles.create(
            type, name: "alpha", projectURL: fixture.root)
        let listed = try ClaudeProjectFiles.enumerate(type, projectURL: fixture.root)
        #expect(listed.map(\.standardizedFileURL.path) == [created.standardizedFileURL.path])
    }

    @Test("enumerate(.agents) walks nested subfolders")
    func enumerateAgentsRecursive() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/agents/reviewer.md", content: "a")
        try fixture.makeFile(at: ".claude/agents/team/lead.md", content: "b")
        try fixture.makeFile(at: ".claude/agents/team/jr.md", content: "c")
        try fixture.makeFile(at: ".claude/agents/skip.txt", content: "ignored")
        let urls = try ClaudeProjectFiles.enumerate(.agents, projectURL: fixture.root)
        let names = urls.map(\.lastPathComponent)
        #expect(names.contains("reviewer.md"))
        #expect(names.contains("lead.md"))
        #expect(names.contains("jr.md"))
        #expect(!names.contains("skip.txt"))
        #expect(urls.count == 3)
    }

    @Test("enumerate(.rules) walks nested subfolders")
    func enumerateRulesRecursive() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/rules/style.md", content: "a")
        try fixture.makeFile(at: ".claude/rules/api/sla.md", content: "b")
        let urls = try ClaudeProjectFiles.enumerate(.rules, projectURL: fixture.root)
        let names = urls.map(\.lastPathComponent)
        #expect(names.contains("style.md"))
        #expect(names.contains("sla.md"))
        #expect(urls.count == 2)
    }

    @Test("enumerate(.outputStyles) is NOT recursive — sibling dirs are ignored")
    func enumerateOutputStylesNotRecursive() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/output-styles/yaml.md", content: "x")
        try fixture.makeFile(at: ".claude/output-styles/archive/old.md", content: "skip")
        let urls = try ClaudeProjectFiles.enumerate(.outputStyles, projectURL: fixture.root)
        let names = urls.map(\.lastPathComponent)
        #expect(names == ["yaml.md"])
    }

    @Test("create(.agents, \"team/lead.md\") writes the nested file and creates intermediate dir")
    func createNestedAgentFileCreatesIntermediateDir() throws {
        let fixture = try ClaudeFilesFixture()
        let url = try ClaudeProjectFiles.create(
            .agents, name: "team/lead.md", projectURL: fixture.root)
        #expect(url.path.hasSuffix(".claude/agents/team/lead.md"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        // Stub's frontmatter `name:` uses the leaf stem, not the nested path.
        let body = try String(contentsOf: url, encoding: .utf8)
        #expect(body.contains("name: lead"))
        #expect(!body.contains("name: team/lead"))
    }

    @Test("create(.rules, \"api/sla\") fills in the default extension under the nested dir")
    func createNestedRuleWithoutExtension() throws {
        let fixture = try ClaudeFilesFixture()
        let url = try ClaudeProjectFiles.create(
            .rules, name: "api/sla", projectURL: fixture.root)
        #expect(url.path.hasSuffix(".claude/rules/api/sla.md"))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("create(.docs, \"team/intro.md\") flattens the slash — docs is non-recursive")
    func createDocFlattensSlash() throws {
        let fixture = try ClaudeFilesFixture()
        let url = try ClaudeProjectFiles.create(
            .docs, name: "team/intro.md", projectURL: fixture.root)
        // Slash is collapsed to `-` so the file stays at the docs root.
        #expect(url.lastPathComponent == "team-intro.md")
        #expect(url.deletingLastPathComponent().lastPathComponent == "docs")
    }

    @Test("create(.outputStyles, \"a/b\") flattens the slash and adds .md")
    func createOutputStyleFlattensSlash() throws {
        let fixture = try ClaudeFilesFixture()
        let url = try ClaudeProjectFiles.create(
            .outputStyles, name: "a/b", projectURL: fixture.root)
        #expect(url.lastPathComponent == "a-b.md")
        #expect(url.deletingLastPathComponent().lastPathComponent == "output-styles")
    }

    @Test("create(.agents) twice with the same nested name walks the suffix in place")
    func createNestedAgentSuffixWalk() throws {
        let fixture = try ClaudeFilesFixture()
        let first = try ClaudeProjectFiles.create(
            .agents, name: "team/lead.md", projectURL: fixture.root)
        let second = try ClaudeProjectFiles.create(
            .agents, name: "team/lead.md", projectURL: fixture.root)
        #expect(first.path.hasSuffix(".claude/agents/team/lead.md"))
        #expect(second.path.hasSuffix(".claude/agents/team/lead-1.md"))
    }

    @Test("enumerate(.agents) does not follow a symlink loop")
    func enumerateAgentsSkipsSymlinkLoop() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/agents/reviewer.md", content: "real")
        let agentsDir = fixture.root.appendingPathComponent(".claude/agents", isDirectory: true)
        let loop = agentsDir.appendingPathComponent("loop", isDirectory: true)
        // Self-referential symlink that would otherwise drive the enumerator
        // into an infinite descent.
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: agentsDir)
        let urls = try ClaudeProjectFiles.enumerate(.agents, projectURL: fixture.root)
        // Only the real file shows up — the symlink and anything reachable
        // through it are ignored.
        #expect(urls.map(\.lastPathComponent) == ["reviewer.md"])
    }

    @Test("enumerate(.agents) ignores file symlinks at the top level")
    func enumerateAgentsSkipsFileSymlink() throws {
        let fixture = try ClaudeFilesFixture()
        try fixture.makeFile(at: ".claude/agents/reviewer.md", content: "real")
        let agentsDir = fixture.root.appendingPathComponent(".claude/agents", isDirectory: true)
        let link = agentsDir.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: agentsDir.appendingPathComponent("reviewer.md"))
        let urls = try ClaudeProjectFiles.enumerate(.agents, projectURL: fixture.root)
        #expect(urls.map(\.lastPathComponent) == ["reviewer.md"])
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
