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

    @Test("Codable round-trip for issue")
    func codableIssue() throws {
        let route: NavigatorRoute = .issue(folderName: "00007-new-issue")
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == route)
    }

    @Test("Codable round-trip for kanban")
    func codableKanban() throws {
        let data = try JSONEncoder().encode(NavigatorRoute.kanban)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == .kanban)
    }

    @Test("Codable round-trip for projectFile")
    func codableProjectFile() throws {
        let route: NavigatorRoute = .projectFile(relativePath: ".claude/agents/team/lead.md")
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == route)
    }

    @Test("Codable round-trip for projectSettings")
    func codableProjectSettings() throws {
        let data = try JSONEncoder().encode(NavigatorRoute.projectSettings)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == .projectSettings)
    }

    @Test("SettingsFile cases cover both files")
    func settingsCases() {
        #expect(SettingsFile.allCases == [.main, .local])
        #expect(SettingsFile.main.rawValue == "settings.json")
        #expect(SettingsFile.local.rawValue == "settings.local.json")
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

    @Test("persistedString migrates legacy .managedFile per type", arguments: ManagedFileType.allCases)
    func persistedStringMigrationManagedFile(type: ManagedFileType) {
        let legacy: NavigatorRoute = .managedFile(type: type, relativePath: "alpha.\(type.defaultExtension)")
        let decoded = NavigatorRoute(persistedString: legacy.persistedString)
        #expect(
            decoded
                == .projectFile(
                    relativePath: "\(type.relativePath)/alpha.\(type.defaultExtension)"))
    }

    @Test("persistedString migrates legacy .claudeMD")
    func persistedStringMigrationClaudeMD() {
        let decoded = NavigatorRoute(persistedString: NavigatorRoute.claudeMD.persistedString)
        #expect(decoded == .projectFile(relativePath: ".claude/CLAUDE.md"))
    }

    @Test("persistedString migrates legacy .claudeLocalMD")
    func persistedStringMigrationClaudeLocalMD() {
        let decoded = NavigatorRoute(
            persistedString: NavigatorRoute.claudeLocalMD.persistedString)
        #expect(decoded == .projectFile(relativePath: ".claude/CLAUDE.local.md"))
    }

    @Test("persistedString migrates legacy .claudeMarkdown")
    func persistedStringMigrationClaudeMarkdown() {
        let decoded = NavigatorRoute(
            persistedString: NavigatorRoute.claudeMarkdown(name: "PROJECT.md").persistedString)
        #expect(decoded == .projectFile(relativePath: ".claude/PROJECT.md"))
    }

    @Test("persistedString migrates legacy .mcpJSON")
    func persistedStringMigrationMCPJSON() {
        let decoded = NavigatorRoute(persistedString: NavigatorRoute.mcpJSON.persistedString)
        #expect(decoded == .projectFile(relativePath: ".mcp.json"))
    }

    @Test("persistedString migrates legacy .skillFile")
    func persistedStringMigrationSkillFile() {
        let legacy: NavigatorRoute = .skillFile(
            skill: "plumage-implement", relativePath: "scripts/precommit-gate.sh")
        let decoded = NavigatorRoute(persistedString: legacy.persistedString)
        #expect(
            decoded
                == .projectFile(
                    relativePath: ".claude/skills/plumage-implement/scripts/precommit-gate.sh"))
    }

    @Test("persistedString migrates legacy .settings(.main)")
    func persistedStringMigrationSettingsMain() {
        let decoded = NavigatorRoute(
            persistedString: NavigatorRoute.settings(.main).persistedString)
        #expect(decoded == .projectFile(relativePath: ".claude/settings.json"))
    }

    @Test("persistedString migrates legacy .settings(.local)")
    func persistedStringMigrationSettingsLocal() {
        let decoded = NavigatorRoute(
            persistedString: NavigatorRoute.settings(.local).persistedString)
        #expect(decoded == .projectFile(relativePath: ".claude/settings.local.json"))
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
        // Simulates a SceneStorage value persisted under a case that no
        // longer exists in any form (no migration mapping).
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
