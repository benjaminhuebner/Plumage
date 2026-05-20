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

    @Test("doc equality is path based")
    func docEquality() {
        let first: NavigatorRoute = .doc(relativePath: ".claude/docs/PROJECT.md")
        let same: NavigatorRoute = .doc(relativePath: ".claude/docs/PROJECT.md")
        let other: NavigatorRoute = .doc(relativePath: ".claude/docs/decisions.md")
        #expect(first == same)
        #expect(first != other)
    }

    @Test("claudeMD compares equal to itself only")
    func claudeMDIdentity() {
        #expect(NavigatorRoute.claudeMD == NavigatorRoute.claudeMD)
        #expect(NavigatorRoute.claudeMD != NavigatorRoute.doc(relativePath: "CLAUDE.md"))
    }

    @Test("hook equality is name based")
    func hookEquality() {
        #expect(NavigatorRoute.hook(name: "swiftlint.sh") == NavigatorRoute.hook(name: "swiftlint.sh"))
        #expect(NavigatorRoute.hook(name: "lint.sh") != NavigatorRoute.hook(name: "test.sh"))
    }

    @Test("skillFile equality requires both skill and relativePath")
    func skillFileEquality() {
        let first: NavigatorRoute = .skillFile(skill: "axiom-build", relativePath: "skills/build.md")
        let same: NavigatorRoute = .skillFile(skill: "axiom-build", relativePath: "skills/build.md")
        let otherSkill: NavigatorRoute = .skillFile(skill: "axiom-swiftui", relativePath: "skills/build.md")
        let otherPath: NavigatorRoute = .skillFile(skill: "axiom-build", relativePath: "skills/other.md")
        #expect(first == same)
        #expect(first != otherSkill)
        #expect(first != otherPath)
    }

    @Test("settings(.main) and settings(.local) are distinct")
    func settingsDistinct() {
        #expect(NavigatorRoute.settings(.main) != NavigatorRoute.settings(.local))
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

    @Test("Codable round-trip for doc")
    func codableDoc() throws {
        let route: NavigatorRoute = .doc(relativePath: ".claude/docs/PROJECT.md")
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == route)
    }

    @Test("Codable round-trip for claudeMD")
    func codableClaudeMD() throws {
        let data = try JSONEncoder().encode(NavigatorRoute.claudeMD)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == .claudeMD)
    }

    @Test("Codable round-trip for hook")
    func codableHook() throws {
        let route: NavigatorRoute = .hook(name: "block-git-commit.sh")
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == route)
    }

    @Test("Codable round-trip for skillFile")
    func codableSkillFile() throws {
        let route: NavigatorRoute = .skillFile(skill: "axiom-build", relativePath: "references/build.md")
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == route)
    }

    @Test("Codable round-trip for claudeMarkdown")
    func codableClaudeMarkdown() throws {
        let route: NavigatorRoute = .claudeMarkdown(name: "PROJECT.md")
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == route)
    }

    @Test("claudeMarkdown equality is name based and distinct from claudeMD")
    func claudeMarkdownEquality() {
        let first: NavigatorRoute = .claudeMarkdown(name: "PROJECT.md")
        let same: NavigatorRoute = .claudeMarkdown(name: "PROJECT.md")
        let other: NavigatorRoute = .claudeMarkdown(name: "notes.md")
        #expect(first == same)
        #expect(first != other)
        #expect(first != .claudeMD)
    }

    @Test("Codable round-trip for settings(.main)")
    func codableSettingsMain() throws {
        let data = try JSONEncoder().encode(NavigatorRoute.settings(.main))
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == .settings(.main))
    }

    @Test("Codable round-trip for settings(.local)")
    func codableSettingsLocal() throws {
        let data = try JSONEncoder().encode(NavigatorRoute.settings(.local))
        let decoded = try JSONDecoder().decode(NavigatorRoute.self, from: data)
        #expect(decoded == .settings(.local))
    }

    @Test("SettingsFile cases cover both files")
    func settingsCases() {
        #expect(SettingsFile.allCases == [.main, .local])
        #expect(SettingsFile.main.rawValue == "settings.json")
        #expect(SettingsFile.local.rawValue == "settings.local.json")
    }

    @Test(
        "persistedString round-trips every case shape",
        arguments: [
            NavigatorRoute.kanban,
            .issue(folderName: "00024-project-navigator"),
            .doc(relativePath: ".claude/docs/PROJECT.md"),
            .claudeMD,
            .hook(name: "lint-swift.sh"),
            .skillFile(skill: "plumage-implement", relativePath: "scripts/precommit-gate.sh"),
            .settings(.main),
            .settings(.local),
        ]
    )
    func persistedStringRoundTrip(route: NavigatorRoute) {
        let encoded = route.persistedString
        let decoded = NavigatorRoute(persistedString: encoded)
        #expect(decoded == route)
    }

    @Test("persistedString init returns nil for empty input")
    func persistedStringEmpty() {
        #expect(NavigatorRoute(persistedString: "") == nil)
    }

    @Test("persistedString init returns nil for invalid JSON")
    func persistedStringInvalid() {
        #expect(NavigatorRoute(persistedString: "not json") == nil)
    }

    @Test("managedFileURL returns nil for routes that aren't a single managed file")
    func managedFileURLNonFileRoutes() {
        let project = URL(filePath: "/tmp/proj")
        #expect(NavigatorRoute.kanban.managedFileURL(in: project) == nil)
        #expect(NavigatorRoute.issue(folderName: "00001-x").managedFileURL(in: project) == nil)
        #expect(NavigatorRoute.claudeMD.managedFileURL(in: project) == nil)
        #expect(NavigatorRoute.settings(.main).managedFileURL(in: project) == nil)
    }

    @Test("managedFileURL builds the correct on-disk URL for managed files")
    func managedFileURLForManagedFiles() {
        let project = URL(filePath: "/tmp/proj")
        #expect(
            NavigatorRoute.doc(relativePath: ".claude/docs/intro.md")
                .managedFileURL(in: project)?.path
                == "/tmp/proj/.claude/docs/intro.md")
        #expect(
            NavigatorRoute.claudeMarkdown(name: "PROJECT.md")
                .managedFileURL(in: project)?.path
                == "/tmp/proj/.claude/PROJECT.md")
        #expect(
            NavigatorRoute.hook(name: "lint.sh")
                .managedFileURL(in: project)?.path
                == "/tmp/proj/.claude/hooks/lint.sh")
        #expect(
            NavigatorRoute.skillFile(skill: "alpha", relativePath: "refs/notes.md")
                .managedFileURL(in: project)?.path
                == "/tmp/proj/.claude/skills/alpha/refs/notes.md")
    }
}
