import Foundation
import Testing

@testable import Plumage

@Suite("EvidenceParser")
struct EvidenceParserTests {
    @Test("valid full file parses identity, task records, and final gate")
    func validFullFile() throws {
        let json = """
            {
              "version": 1,
              "issue": "00042-add-user-auth",
              "branch": "issue/00042-add-user-auth",
              "totalTasks": 3,
              "tasks": [
                {"task": 1, "attempts": 1, "passedAt": "2026-07-02T10:00:00Z", "head": "abc123", "flags": []},
                {"task": 2, "attempts": 3, "passedAt": "2026-07-02T11:30:00Z", "head": "def456", "flags": ["--skip-build"]}
              ],
              "finalGate": {"attempts": 1, "passedAt": "2026-07-02T12:00:00Z", "head": "0a1b2c", "flags": ["--full"]}
            }
            """
        let evidence = try EvidenceParser.parse(data: Data(json.utf8)).get()
        #expect(evidence.version == 1)
        #expect(evidence.issue == "00042-add-user-auth")
        #expect(evidence.branch == "issue/00042-add-user-auth")
        #expect(evidence.totalTasks == 3)
        #expect(evidence.tasks.count == 2)
        #expect(evidence.tasks[0].task == 1)
        #expect(evidence.tasks[0].attempts == 1)
        #expect(evidence.tasks[0].passedAt == ISO8601Flexible.date(from: "2026-07-02T10:00:00Z"))
        #expect(evidence.tasks[0].head == "abc123")
        #expect(evidence.tasks[0].flags.isEmpty)
        #expect(evidence.tasks[1].attempts == 3)
        #expect(evidence.tasks[1].flags == ["--skip-build"])
        let finalGate = try #require(evidence.finalGate)
        #expect(finalGate.attempts == 1)
        #expect(finalGate.passedAt == ISO8601Flexible.date(from: "2026-07-02T12:00:00Z"))
        #expect(finalGate.head == "0a1b2c")
        #expect(finalGate.flags == ["--full"])
    }

    @Test("partial file: attempts-only record, no final gate, missing optionals")
    func partialFile() throws {
        let json = """
            {
              "version": 1,
              "issue": "00042-add-user-auth",
              "tasks": [
                {"task": 1, "attempts": 2}
              ]
            }
            """
        let evidence = try EvidenceParser.parse(data: Data(json.utf8)).get()
        #expect(evidence.branch == nil)
        #expect(evidence.totalTasks == nil)
        #expect(evidence.finalGate == nil)
        let record = try #require(evidence.tasks.first)
        #expect(record.task == 1)
        #expect(record.attempts == 2)
        #expect(record.passedAt == nil)
        #expect(record.head == nil)
        #expect(record.flags.isEmpty)
    }

    @Test("missing tasks array defaults to empty")
    func missingTasksArray() throws {
        let json = """
            {"version": 1, "issue": "00042-add-user-auth"}
            """
        let evidence = try EvidenceParser.parse(data: Data(json.utf8)).get()
        #expect(evidence.tasks.isEmpty)
    }

    @Test("truncated file is invalid JSON")
    func truncatedFile() throws {
        let json = """
            {"version": 1, "issue": "00042-add-user-auth", "tasks": [{"task": 1,
            """
        let error = try #require(failure(json))
        guard case .invalidJSON = error else {
            Testing.Issue.record("expected invalidJSON, got \(error)")
            return
        }
    }

    @Test("empty data is invalid JSON")
    func emptyData() throws {
        let error = try #require(failure(""))
        guard case .invalidJSON = error else {
            Testing.Issue.record("expected invalidJSON, got \(error)")
            return
        }
    }

    @Test("missing required field is typed with the field name")
    func missingRequiredField() throws {
        let error = try #require(failure(#"{"version": 1}"#))
        #expect(error == .missingRequiredField(name: "issue"))
    }

    @Test("wrong field type is typed with the field name")
    func wrongFieldType() throws {
        let json = """
            {"version": 1, "issue": "x", "tasks": [{"task": "one", "attempts": 1}]}
            """
        let error = try #require(failure(json))
        guard case .invalidFieldValue(let field, _) = error else {
            Testing.Issue.record("expected invalidFieldValue, got \(error)")
            return
        }
        #expect(field == "task")
    }

    @Test("invalid date string is typed with the field name")
    func invalidDate() throws {
        let json = """
            {"version": 1, "issue": "x", "tasks": [{"task": 1, "attempts": 1, "passedAt": "yesterday"}]}
            """
        let error = try #require(failure(json))
        guard case .invalidFieldValue(let field, _) = error else {
            Testing.Issue.record("expected invalidFieldValue, got \(error)")
            return
        }
        #expect(field == "passedAt")
    }

    private func failure(_ json: String) -> EvidenceParseError? {
        if case .failure(let error) = EvidenceParser.parse(data: Data(json.utf8)) {
            return error
        }
        return nil
    }
}
