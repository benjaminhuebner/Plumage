import Foundation
import Testing

@testable import Plumage

@Suite("FrontmatterError")
struct FrontmatterErrorTests {
    @Test("missingFrontmatter equals itself")
    func missingFrontmatterEquality() {
        #expect(FrontmatterError.missingFrontmatter == .missingFrontmatter)
    }

    @Test("invalidYAML equality compares line and message")
    func invalidYAMLEquality() {
        #expect(
            FrontmatterError.invalidYAML(line: 3, message: "x")
                == .invalidYAML(line: 3, message: "x")
        )
        #expect(
            FrontmatterError.invalidYAML(line: 3, message: "x")
                != .invalidYAML(line: 4, message: "x")
        )
        #expect(
            FrontmatterError.invalidYAML(line: 3, message: "x")
                != .invalidYAML(line: 3, message: "y")
        )
        #expect(
            FrontmatterError.invalidYAML(line: nil, message: "x")
                == .invalidYAML(line: nil, message: "x")
        )
    }

    @Test("missingRequiredField equality compares name")
    func missingRequiredFieldEquality() {
        #expect(
            FrontmatterError.missingRequiredField(name: "id")
                == .missingRequiredField(name: "id")
        )
        #expect(
            FrontmatterError.missingRequiredField(name: "id")
                != .missingRequiredField(name: "title")
        )
    }

    @Test("invalidEnumValue equality compares field and value")
    func invalidEnumValueEquality() {
        #expect(
            FrontmatterError.invalidEnumValue(field: "type", value: "x")
                == .invalidEnumValue(field: "type", value: "x")
        )
        #expect(
            FrontmatterError.invalidEnumValue(field: "type", value: "x")
                != .invalidEnumValue(field: "status", value: "x")
        )
        #expect(
            FrontmatterError.invalidEnumValue(field: "type", value: "x")
                != .invalidEnumValue(field: "type", value: "y")
        )
    }

    @Test("invalidDate equality compares field and value")
    func invalidDateEquality() {
        #expect(
            FrontmatterError.invalidDate(field: "created", value: "x")
                == .invalidDate(field: "created", value: "x")
        )
        #expect(
            FrontmatterError.invalidDate(field: "created", value: "x")
                != .invalidDate(field: "updated", value: "x")
        )
    }

    @Test("different cases are not equal")
    func crossCaseInequality() {
        #expect(FrontmatterError.missingFrontmatter != .missingRequiredField(name: "id"))
        #expect(
            FrontmatterError.invalidYAML(line: 1, message: "m")
                != .invalidEnumValue(field: "type", value: "m")
        )
    }

    @Test("unreadable equality compares message")
    func unreadableEquality() {
        #expect(
            FrontmatterError.unreadable(message: "permission denied")
                == .unreadable(message: "permission denied")
        )
        #expect(
            FrontmatterError.unreadable(message: "x")
                != .unreadable(message: "y")
        )
        #expect(FrontmatterError.unreadable(message: "x") != .missingFrontmatter)
    }

    @Test("invalidFieldType equality compares field and message")
    func invalidFieldTypeEquality() {
        #expect(
            FrontmatterError.invalidFieldType(field: "id", message: "m")
                == .invalidFieldType(field: "id", message: "m")
        )
        #expect(
            FrontmatterError.invalidFieldType(field: "id", message: "m")
                != .invalidFieldType(field: "title", message: "m")
        )
        #expect(
            FrontmatterError.invalidFieldType(field: "id", message: "m")
                != .invalidFieldType(field: "id", message: "n")
        )
    }

    @Test("missingFrontmatter summary and description")
    func missingFrontmatterDisplay() {
        let err = FrontmatterError.missingFrontmatter
        #expect(err.summary == "No --- frontmatter block found")
        #expect(err.description.hasPrefix("No --- frontmatter block found."))
        #expect(err.description.contains("YAML frontmatter"))
    }

    @Test("invalidYAML with line uses line in summary and description")
    func invalidYAMLWithLineDisplay() {
        let err = FrontmatterError.invalidYAML(line: 7, message: "unclosed quote")
        #expect(err.summary == "YAML error at line 7")
        #expect(err.description == "YAML error at line 7: unclosed quote")
    }

    @Test("invalidYAML without line falls back to generic summary")
    func invalidYAMLWithoutLineDisplay() {
        let err = FrontmatterError.invalidYAML(line: nil, message: "boom")
        #expect(err.summary == "Invalid YAML in frontmatter")
        #expect(err.description == "Invalid YAML in frontmatter: boom")
    }

    @Test("missingRequiredField summary and description")
    func missingRequiredFieldDisplay() {
        let err = FrontmatterError.missingRequiredField(name: "branch")
        #expect(err.summary == "Missing required field: branch")
        #expect(err.description.contains("branch"))
        #expect(err.description.contains("id, title, type, status, created, updated, branch"))
    }

    @Test("invalidEnumValue for type lists allowed types")
    func invalidEnumValueTypeDisplay() {
        let err = FrontmatterError.invalidEnumValue(field: "type", value: "experiment")
        #expect(err.summary == "Unknown type: 'experiment'")
        #expect(err.description.contains("Unknown type: 'experiment'"))
        #expect(err.description.contains("feature"))
        #expect(err.description.contains("chore"))
        #expect(err.description.contains("spike"))
    }

    @Test("invalidEnumValue for status lists allowed statuses")
    func invalidEnumValueStatusDisplay() {
        let err = FrontmatterError.invalidEnumValue(field: "status", value: "aproved")
        #expect(err.summary == "Unknown status: 'aproved'")
        #expect(err.description.contains("approved"))
        #expect(err.description.contains("in-progress"))
        #expect(err.description.contains("done"))
    }

    @Test("invalidDate summary and description")
    func invalidDateDisplay() {
        let err = FrontmatterError.invalidDate(field: "created", value: "2026-13-99")
        #expect(err.summary == "Invalid date in created: '2026-13-99'")
        #expect(err.description.contains("Invalid date in created: '2026-13-99'"))
        #expect(err.description.contains("ISO-8601"))
    }

    @Test("unreadable summary and description")
    func unreadableDisplay() {
        let err = FrontmatterError.unreadable(message: "permission denied")
        #expect(err.summary == "spec.md could not be read")
        #expect(err.description == "spec.md could not be read: permission denied")
    }

    @Test("invalidFieldType summary and description")
    func invalidFieldTypeDisplay() {
        let err = FrontmatterError.invalidFieldType(field: "id", message: "expected Int")
        #expect(err.summary == "Invalid type for field: id")
        #expect(err.description.contains("id"))
        #expect(err.description.contains("expected Int"))
    }
}
