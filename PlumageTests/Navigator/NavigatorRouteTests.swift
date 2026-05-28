import Foundation
import Testing

@testable import Plumage

@Suite("NavigatorRoute")
struct NavigatorRouteTests {
    @Test("kanban is distinct from issue case")
    func kanbanIsDistinct() {
        let kanban: NavigatorRoute = .kanban
        let issue: NavigatorRoute = .issue(folderName: "00001-x")
        #expect(kanban != issue)
    }

    @Test("issue equality is folder-name based")
    func issueEquality() {
        #expect(NavigatorRoute.issue(folderName: "00001") == NavigatorRoute.issue(folderName: "00001"))
        #expect(NavigatorRoute.issue(folderName: "00001") != NavigatorRoute.issue(folderName: "00002"))
    }

    @Test("projectFile equality is path based")
    func projectFileEquality() {
        let first: NavigatorRoute = .projectFile(relativePath: ".claude/docs/intro.md")
        let same: NavigatorRoute = .projectFile(relativePath: ".claude/docs/intro.md")
        let other: NavigatorRoute = .projectFile(relativePath: ".claude/docs/other.md")
        #expect(first == same)
        #expect(first != other)
        #expect(first != .kanban)
        #expect(first != .projectSettings)
    }

    @Test("kanban Hashable round-trip preserves equality")
    func kanbanHashable() {
        let set: Set<NavigatorRoute> = [.kanban, .kanban, .issue(folderName: "00001")]
        #expect(set.count == 2)
    }

    @Test(
        "persistedString round-trips structural cases",
        arguments: [
            NavigatorRoute.kanban,
            .issue(folderName: "00024-project-navigator"),
            .projectSettings,
            .projectFile(relativePath: ".claude/docs/PROJECT.md"),
            .projectFile(relativePath: ".claude/hooks/lint-swift.sh"),
            .projectFile(relativePath: ".claude/agents/team/reviewer.md"),
            .projectFile(relativePath: ".mcp.json"),
            .projectFile(relativePath: ".claude/CLAUDE.md"),
            .projectFile(relativePath: ".claude/skills/plumage-implement/scripts/precommit-gate.sh"),
        ]
    )
    func persistedStringRoundTrip(route: NavigatorRoute) {
        let encoded = route.persistedString
        let decoded = NavigatorRoute(persistedString: encoded)
        #expect(decoded == route)
    }

    @Test(
        "persistedString migrates pre-collapse .managedFile JSON shapes",
        arguments: [
            ("docs", ".claude/docs/PROJECT.md"),
            ("hooks", ".claude/hooks/lint.sh"),
            ("agents", ".claude/agents/team/lead.md"),
            ("rules", ".claude/rules/style.md"),
            ("outputStyles", ".claude/output-styles/yaml.md"),
        ]
    )
    func migrateLegacyManagedFile(typeRaw: String, expected: String) {
        let rel = String(expected.split(separator: "/").dropFirst(2).joined(separator: "/"))
        let json = #"{"managedFile":{"type":"\#(typeRaw)","relativePath":"\#(rel)"}}"#
        #expect(NavigatorRoute(persistedString: json) == .projectFile(relativePath: expected))
    }

    @Test("persistedString migrates legacy .claudeMD")
    func migrateLegacyClaudeMD() {
        #expect(
            NavigatorRoute(persistedString: #"{"claudeMD":{}}"#)
                == .projectFile(relativePath: ".claude/CLAUDE.md"))
    }

    @Test("persistedString migrates legacy .claudeLocalMD")
    func migrateLegacyClaudeLocalMD() {
        #expect(
            NavigatorRoute(persistedString: #"{"claudeLocalMD":{}}"#)
                == .projectFile(relativePath: ".claude/CLAUDE.local.md"))
    }

    @Test("persistedString migrates legacy .claudeMarkdown")
    func migrateLegacyClaudeMarkdown() {
        #expect(
            NavigatorRoute(persistedString: #"{"claudeMarkdown":{"name":"PROJECT.md"}}"#)
                == .projectFile(relativePath: ".claude/PROJECT.md"))
    }

    @Test("persistedString migrates legacy .mcpJSON")
    func migrateLegacyMCPJSON() {
        #expect(
            NavigatorRoute(persistedString: #"{"mcpJSON":{}}"#)
                == .projectFile(relativePath: ".mcp.json"))
    }

    @Test("persistedString migrates legacy .skillFile")
    func migrateLegacySkillFile() {
        let json = #"{"skillFile":{"skill":"plumage-implement","relativePath":"scripts/precommit-gate.sh"}}"#
        #expect(
            NavigatorRoute(persistedString: json)
                == .projectFile(
                    relativePath: ".claude/skills/plumage-implement/scripts/precommit-gate.sh"))
    }

    @Test("persistedString migrates legacy .settings(.main)")
    func migrateLegacySettingsMain() {
        let json = #"{"settings":{"_0":"settings.json"}}"#
        #expect(
            NavigatorRoute(persistedString: json)
                == .projectFile(relativePath: ".claude/settings.json"))
    }

    @Test("persistedString migrates legacy .settings(.local)")
    func migrateLegacySettingsLocal() {
        let json = #"{"settings":{"_0":"settings.local.json"}}"#
        #expect(
            NavigatorRoute(persistedString: json)
                == .projectFile(relativePath: ".claude/settings.local.json"))
    }

    @Test("persistedString returns nil for empty input")
    func persistedStringEmpty() {
        #expect(NavigatorRoute(persistedString: "") == nil)
    }

    @Test("persistedString returns nil for invalid JSON")
    func persistedStringInvalid() {
        #expect(NavigatorRoute(persistedString: "not json") == nil)
    }

    @Test("persistedString returns nil for an unknown enum tag")
    func persistedStringUnknownTag() {
        let legacy = #"{"doc":{"_0":".claude/docs/old.md"}}"#
        #expect(NavigatorRoute(persistedString: legacy) == nil)
    }

    @Test("managedFileURL returns nil for routes that aren't a single file")
    func managedFileURLNonFileRoutes() {
        let project = URL(filePath: "/tmp/proj")
        #expect(NavigatorRoute.kanban.managedFileURL(in: project) == nil)
        #expect(NavigatorRoute.issue(folderName: "00001-x").managedFileURL(in: project) == nil)
        #expect(NavigatorRoute.projectSettings.managedFileURL(in: project) == nil)
    }

    @Test("managedFileURL builds the on-disk URL for .projectFile")
    func managedFileURLForProjectFile() {
        let project = URL(filePath: "/tmp/proj")
        #expect(
            NavigatorRoute.projectFile(relativePath: ".claude/docs/intro.md")
                .managedFileURL(in: project)?.path
                == "/tmp/proj/.claude/docs/intro.md")
        #expect(
            NavigatorRoute.projectFile(relativePath: ".mcp.json")
                .managedFileURL(in: project)?.path
                == "/tmp/proj/.mcp.json")
    }
}
