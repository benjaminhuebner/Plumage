import Foundation
import LanguageSupport
import Testing

@testable import Plumage

@Suite("FrontmatterMessageMap")
struct FrontmatterMessageMapTests {
    @Test("invalidYAML with line and column maps to that location")
    func invalidYAMLWithLineAndColumn() {
        let err = FrontmatterError.invalidYAML(line: 7, column: 12, message: "boom")
        let loc = FrontmatterMessageMap.location(for: err)
        #expect(loc.line == 7)
        #expect(loc.column == 12)
    }

    @Test("invalidYAML with line but nil column falls back to column 1")
    func invalidYAMLWithLineNilColumn() {
        let err = FrontmatterError.invalidYAML(line: 5, column: nil, message: "boom")
        let loc = FrontmatterMessageMap.location(for: err)
        #expect(loc.line == 5)
        #expect(loc.column == 1)
    }

    @Test("invalidYAML with nil line falls back to (1, 1)")
    func invalidYAMLNilLine() {
        let err = FrontmatterError.invalidYAML(line: nil, column: nil, message: "boom")
        let loc = FrontmatterMessageMap.location(for: err)
        #expect(loc.line == 1)
        #expect(loc.column == 1)
    }

    @Test("missingFrontmatter maps to (1, 1)")
    func missingFrontmatter() {
        let loc = FrontmatterMessageMap.location(for: .missingFrontmatter)
        #expect(loc.line == 1)
        #expect(loc.column == 1)
    }

    @Test("missingRequiredField anchors to (2, 1)")
    func missingRequiredField() {
        let loc = FrontmatterMessageMap.location(for: .missingRequiredField(name: "id"))
        #expect(loc.line == 2)
        #expect(loc.column == 1)
    }

    @Test("invalidEnumValue anchors to (2, 1)")
    func invalidEnumValue() {
        let loc = FrontmatterMessageMap.location(for: .invalidEnumValue(field: "type", value: "x"))
        #expect(loc.line == 2)
        #expect(loc.column == 1)
    }

    @Test("invalidDate anchors to (2, 1)")
    func invalidDate() {
        let loc = FrontmatterMessageMap.location(for: .invalidDate(field: "created", value: "x"))
        #expect(loc.line == 2)
        #expect(loc.column == 1)
    }

    @Test("invalidFieldType anchors to (2, 1)")
    func invalidFieldType() {
        let loc = FrontmatterMessageMap.location(for: .invalidFieldType(field: "id", message: "x"))
        #expect(loc.line == 2)
        #expect(loc.column == 1)
    }

    @Test("unreadable maps to (1, 1)")
    func unreadable() {
        let loc = FrontmatterMessageMap.location(for: .unreadable(message: "denied"))
        #expect(loc.line == 1)
        #expect(loc.column == 1)
    }

    @Test("message(for:) returns category .error with summary populated")
    func messagePayload() {
        let err = FrontmatterError.invalidYAML(line: 7, column: 12, message: "boom")
        let located = FrontmatterMessageMap.message(for: err)
        #expect(located.entity.category == .error)
        #expect(located.entity.summary == "YAML error at line 7, column 12")
        #expect(located.location.oneBasedLine == 7)
        #expect(located.location.oneBasedColumn == 12)
    }
}
