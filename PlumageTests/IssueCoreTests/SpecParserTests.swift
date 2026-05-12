import Foundation
import Testing

@testable import Plumage

@Suite("SpecParser")
struct SpecParserTests {
    @Test("parses feature fixture")
    func validFeature() throws {
        let issue = try #require(SpecParser.parse(content: load("valid-feature.md"), folder: "00042-feature"))
        #expect(issue.id == 42)
        #expect(issue.folder == "00042-feature")
        #expect(issue.title == "Feature Issue")
        #expect(issue.type == .feature)
        #expect(issue.status == .approved)
        #expect(issue.branch == "issue/00042-feature")
        #expect(issue.labels == ["feature", "v0.1"])
        #expect(issue.model == "claude-opus-4-7")
        #expect(issue.created == iso("2026-05-12T09:00:00Z"))
        #expect(issue.updated == iso("2026-05-12T10:30:00Z"))
    }

    @Test("parses chore with empty labels and null model")
    func validChore() throws {
        let issue = try #require(SpecParser.parse(content: load("valid-chore.md"), folder: "00001-chore"))
        #expect(issue.type == .chore)
        #expect(issue.status == .inProgress)
        #expect(issue.labels.isEmpty)
        #expect(issue.model == nil)
    }

    @Test("parses spike with fractional-second updated date")
    func validSpike() throws {
        let issue = try #require(SpecParser.parse(content: load("valid-spike.md"), folder: "00002-spike"))
        #expect(issue.type == .spike)
        #expect(issue.status == .waitingForReview)
        #expect(issue.updated == isoFractional("2026-05-12T09:15:30.123Z"))
    }

    @Test("returns nil for missing frontmatter delimiter")
    func missingFrontmatter() {
        #expect(SpecParser.parse(content: load("missing-frontmatter.md"), folder: "x") == nil)
    }

    @Test("returns nil for empty input")
    func emptyInput() {
        #expect(SpecParser.parse(content: "", folder: "x") == nil)
    }

    @Test("returns nil for broken YAML")
    func brokenYAML() {
        #expect(SpecParser.parse(content: load("broken-yaml.md"), folder: "x") == nil)
    }

    @Test("returns nil for unknown type value")
    func unknownType() {
        #expect(SpecParser.parse(content: load("unknown-type.md"), folder: "x") == nil)
    }

    @Test("returns nil for unknown status value")
    func unknownStatus() {
        #expect(SpecParser.parse(content: load("unknown-status.md"), folder: "x") == nil)
    }

    @Test("returns nil when id is missing")
    func missingId() {
        #expect(SpecParser.parse(content: load("missing-id.md"), folder: "x") == nil)
    }

    @Test("returns nil when title is missing")
    func missingTitle() {
        #expect(SpecParser.parse(content: load("missing-title.md"), folder: "x") == nil)
    }

    @Test("returns nil when closing delimiter is missing")
    func missingClosingDelimiter() {
        let content = """
            ---
            id: 1
            title: t
            type: feature
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00001-x
            labels: []
            model: null
            """
        #expect(SpecParser.parse(content: content, folder: "x") == nil)
    }

    private func load(_ name: String, fileID: String = #fileID, filePath: String = #filePath) -> String {
        let url = URL(filePath: filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func iso(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string) ?? .distantPast
    }

    private func isoFractional(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? .distantPast
    }
}
