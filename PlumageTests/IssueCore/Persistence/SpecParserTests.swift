import Foundation
import Testing

@testable import Plumage

@Suite("SpecParser")
struct SpecParserTests {
    @Test("parses feature fixture")
    func validFeature() throws {
        let issue = try requireSuccess(
            SpecParser.parse(content: try load("valid-feature.md"), folderName: "00042-feature"))
        #expect(issue.id == 42)
        #expect(issue.folderName == "00042-feature")
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
        let issue = try requireSuccess(SpecParser.parse(content: try load("valid-chore.md"), folderName: "00001-chore"))
        #expect(issue.type == .chore)
        #expect(issue.status == .inProgress)
        #expect(issue.labels.isEmpty)
        #expect(issue.model == nil)
    }

    @Test("parses spike with fractional-second updated date")
    func validSpike() throws {
        let issue = try requireSuccess(SpecParser.parse(content: try load("valid-spike.md"), folderName: "00002-spike"))
        #expect(issue.type == .spike)
        #expect(issue.status == .waitingForReview)
        #expect(issue.updated == isoFractional("2026-05-12T09:15:30.123Z"))
    }

    @Test("parses CRLF line endings")
    func crlfLineEndings() throws {
        let content = """
            ---
            id: 9
            title: CRLF spec
            type: chore
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00009-crlf
            ---

            Body.
            """
            .replacingOccurrences(of: "\n", with: "\r\n")
        let issue = try requireSuccess(SpecParser.parse(content: content, folderName: "00009-crlf"))
        #expect(issue.id == 9)
        #expect(issue.title == "CRLF spec")
        #expect(SpecParser.validate(content: content) == nil)
    }

    @Test("tolerates leading blank lines before the opening delimiter")
    func leadingBlankLines() throws {
        let content = """


            ---
            id: 10
            title: t
            type: chore
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00010-x
            ---

            Body.
            """
        let issue = try requireSuccess(SpecParser.parse(content: content, folderName: "00010-x"))
        #expect(issue.id == 10)
    }

    @Test("parses optional mergeSubject when present")
    func mergeSubjectPresent() throws {
        let content = """
            ---
            id: 7
            title: t
            type: feature
            status: waiting-for-review
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00007-x
            labels: []
            model: null
            mergeSubject: Add squash mode to issue merge
            ---

            Body.
            """
        let issue = try requireSuccess(SpecParser.parse(content: content, folderName: "00007-x"))
        #expect(issue.mergeSubject == "Add squash mode to issue merge")
    }

    @Test("mergeSubject is nil when absent")
    func mergeSubjectAbsent() throws {
        let issue = try requireSuccess(
            SpecParser.parse(content: try load("valid-feature.md"), folderName: "00042-feature"))
        #expect(issue.mergeSubject == nil)
    }

    @Test("missing frontmatter delimiter is .missingFrontmatter")
    func missingFrontmatter() throws {
        #expect(
            SpecParser.parse(content: try load("missing-frontmatter.md"), folderName: "x")
                == .failure(.missingFrontmatter))
    }

    @Test("empty input is .missingFrontmatter")
    func emptyInput() throws {
        #expect(SpecParser.parse(content: "", folderName: "x") == .failure(.missingFrontmatter))
    }

    @Test("missing closing delimiter is .missingFrontmatter")
    func missingClosingDelimiter() throws {
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
        #expect(SpecParser.parse(content: content, folderName: "x") == .failure(.missingFrontmatter))
    }

    @Test("broken YAML returns .invalidYAML with line and column info")
    func brokenYAML() throws {
        let result = SpecParser.parse(content: try load("broken-yaml.md"), folderName: "x")
        guard case .failure(.invalidYAML(let line, let column, let message)) = result else {
            Testing.Issue.record("expected .invalidYAML, got \(result)")
            return
        }
        #expect(line != nil)
        #expect(column != nil)
        #expect(!message.isEmpty)
    }

    @Test("broken YAML returns specific column from Yams mark")
    func brokenYAMLColumn() throws {
        // Fixture broken-yaml.md has an unclosed quote on line 3 (1-based): `title: "Broken with unclosed quote`
        // Yams reports line/column on the closing-newline / next-token position.
        let result = SpecParser.parse(content: try load("broken-yaml.md"), folderName: "x")
        guard case .failure(.invalidYAML(let line?, let column?, _)) = result else {
            Testing.Issue.record("expected .invalidYAML with line+column, got \(result)")
            return
        }
        #expect(line >= 1)
        #expect(column >= 1)
    }

    // Coverage gap (non-blocking): the .dataCorrupted-without-underlying-YamlError branch in
    // SpecParser.mapDecodingError is not exercised by any input we could craft with Yams 5.4 —
    // Yams always wraps its own scanner/parser/composer errors as YamlError. Left untested
    // until a future Yams version produces a bare .dataCorrupted.

    @Test("unknown type returns .invalidEnumValue")
    func unknownType() throws {
        #expect(
            SpecParser.parse(content: try load("unknown-type.md"), folderName: "x")
                == .failure(.invalidEnumValue(field: "type", value: "experiment"))
        )
    }

    @Test("unknown status returns .invalidEnumValue")
    func unknownStatus() throws {
        #expect(
            SpecParser.parse(content: try load("unknown-status.md"), folderName: "x")
                == .failure(.invalidEnumValue(field: "status", value: "parked"))
        )
    }

    @Test("missing id returns .missingRequiredField(\"id\")")
    func missingId() throws {
        #expect(
            SpecParser.parse(content: try load("missing-id.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "id"))
        )
    }

    @Test("missing title returns .missingRequiredField(\"title\")")
    func missingTitle() throws {
        #expect(
            SpecParser.parse(content: try load("missing-title.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "title"))
        )
    }

    @Test("missing type returns .missingRequiredField(\"type\")")
    func missingType() throws {
        #expect(
            SpecParser.parse(content: try load("missing-type.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "type"))
        )
    }

    @Test("missing status returns .missingRequiredField(\"status\")")
    func missingStatus() throws {
        #expect(
            SpecParser.parse(content: try load("missing-status.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "status"))
        )
    }

    @Test("missing created returns .missingRequiredField(\"created\")")
    func missingCreated() throws {
        #expect(
            SpecParser.parse(content: try load("missing-created.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "created"))
        )
    }

    @Test("missing updated returns .missingRequiredField(\"updated\")")
    func missingUpdated() throws {
        #expect(
            SpecParser.parse(content: try load("missing-updated.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "updated"))
        )
    }

    @Test("missing branch returns .missingRequiredField(\"branch\")")
    func missingBranch() throws {
        #expect(
            SpecParser.parse(content: try load("missing-branch.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "branch"))
        )
    }

    @Test("invalid date returns .invalidDate")
    func invalidDate() throws {
        #expect(
            SpecParser.parse(content: try load("invalid-date.md"), folderName: "x")
                == .failure(.invalidDate(field: "created", value: "2026-13-99T99:99:99Z"))
        )
    }

    @Test("empty frontmatter body reports a missing required field")
    func emptyFrontmatter() throws {
        #expect(
            SpecParser.parse(content: try load("empty-frontmatter.md"), folderName: "x")
                == .failure(.missingRequiredField(name: "id"))
        )
    }

    @Test("wrong type for id returns .invalidFieldType")
    func wrongTypeForId() throws {
        let result = SpecParser.parse(content: try load("wrong-type-id.md"), folderName: "x")
        guard case .failure(.invalidFieldType(let field, let message)) = result else {
            Testing.Issue.record("expected .invalidFieldType, got \(result)")
            return
        }
        #expect(field == "id")
        #expect(!message.isEmpty)
    }

    @Test("validate returns nil for valid content")
    func validateValid() throws {
        #expect(SpecParser.validate(content: try load("valid-feature.md")) == nil)
    }

    @Test("validate returns the parse failure for invalid content")
    func validateInvalid() throws {
        #expect(SpecParser.validate(content: try load("missing-frontmatter.md")) == .missingFrontmatter)
        #expect(
            SpecParser.validate(content: try load("unknown-type.md"))
                == .invalidEnumValue(field: "type", value: "experiment"))
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

    private func load(_ name: String, filePath: String = #filePath) throws -> String {
        let url = URL(filePath: filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
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
