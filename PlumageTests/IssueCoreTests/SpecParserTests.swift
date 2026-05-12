import Foundation
import Testing

@testable import Plumage

@Suite("SpecParser")
struct SpecParserTests {
    @Test("parses feature fixture")
    func validFeature() throws {
        let issue = try requireSuccess(SpecParser.parse(content: load("valid-feature.md"), folder: "00042-feature"))
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
        let issue = try requireSuccess(SpecParser.parse(content: load("valid-chore.md"), folder: "00001-chore"))
        #expect(issue.type == .chore)
        #expect(issue.status == .inProgress)
        #expect(issue.labels.isEmpty)
        #expect(issue.model == nil)
    }

    @Test("parses spike with fractional-second updated date")
    func validSpike() throws {
        let issue = try requireSuccess(SpecParser.parse(content: load("valid-spike.md"), folder: "00002-spike"))
        #expect(issue.type == .spike)
        #expect(issue.status == .waitingForReview)
        #expect(issue.updated == isoFractional("2026-05-12T09:15:30.123Z"))
    }

    @Test("missing frontmatter delimiter is .missingFrontmatter")
    func missingFrontmatter() {
        #expect(SpecParser.parse(content: load("missing-frontmatter.md"), folder: "x") == .failure(.missingFrontmatter))
    }

    @Test("empty input is .missingFrontmatter")
    func emptyInput() {
        #expect(SpecParser.parse(content: "", folder: "x") == .failure(.missingFrontmatter))
    }

    @Test("missing closing delimiter is .missingFrontmatter")
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
        #expect(SpecParser.parse(content: content, folder: "x") == .failure(.missingFrontmatter))
    }

    @Test("broken YAML returns .invalidYAML with line info")
    func brokenYAML() throws {
        let result = SpecParser.parse(content: load("broken-yaml.md"), folder: "x")
        guard case .failure(.invalidYAML(let line, let message)) = result else {
            Testing.Issue.record("expected .invalidYAML, got \(result)")
            return
        }
        #expect(line != nil)
        #expect(!message.isEmpty)
    }

    @Test("unknown type returns .invalidEnumValue")
    func unknownType() {
        #expect(
            SpecParser.parse(content: load("unknown-type.md"), folder: "x")
                == .failure(.invalidEnumValue(field: "type", value: "experiment"))
        )
    }

    @Test("unknown status returns .invalidEnumValue")
    func unknownStatus() {
        #expect(
            SpecParser.parse(content: load("unknown-status.md"), folder: "x")
                == .failure(.invalidEnumValue(field: "status", value: "parked"))
        )
    }

    @Test("missing id returns .missingRequiredField(\"id\")")
    func missingId() {
        #expect(
            SpecParser.parse(content: load("missing-id.md"), folder: "x")
                == .failure(.missingRequiredField(name: "id"))
        )
    }

    @Test("missing title returns .missingRequiredField(\"title\")")
    func missingTitle() {
        #expect(
            SpecParser.parse(content: load("missing-title.md"), folder: "x")
                == .failure(.missingRequiredField(name: "title"))
        )
    }

    @Test("missing type returns .missingRequiredField(\"type\")")
    func missingType() {
        #expect(
            SpecParser.parse(content: load("missing-type.md"), folder: "x")
                == .failure(.missingRequiredField(name: "type"))
        )
    }

    @Test("missing status returns .missingRequiredField(\"status\")")
    func missingStatus() {
        #expect(
            SpecParser.parse(content: load("missing-status.md"), folder: "x")
                == .failure(.missingRequiredField(name: "status"))
        )
    }

    @Test("missing created returns .missingRequiredField(\"created\")")
    func missingCreated() {
        #expect(
            SpecParser.parse(content: load("missing-created.md"), folder: "x")
                == .failure(.missingRequiredField(name: "created"))
        )
    }

    @Test("missing updated returns .missingRequiredField(\"updated\")")
    func missingUpdated() {
        #expect(
            SpecParser.parse(content: load("missing-updated.md"), folder: "x")
                == .failure(.missingRequiredField(name: "updated"))
        )
    }

    @Test("missing branch returns .missingRequiredField(\"branch\")")
    func missingBranch() {
        #expect(
            SpecParser.parse(content: load("missing-branch.md"), folder: "x")
                == .failure(.missingRequiredField(name: "branch"))
        )
    }

    @Test("invalid date returns .invalidDate")
    func invalidDate() {
        #expect(
            SpecParser.parse(content: load("invalid-date.md"), folder: "x")
                == .failure(.invalidDate(field: "created", value: "2026-13-99T99:99:99Z"))
        )
    }

    private func requireSuccess(
        _ result: Result<Plumage.Issue, FrontmatterError>
    ) throws -> Plumage.Issue {
        switch result {
        case .success(let issue): issue
        case .failure(let err):
            throw RequireFailure(message: "expected success, got \(err)")
        }
    }

    private struct RequireFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
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
