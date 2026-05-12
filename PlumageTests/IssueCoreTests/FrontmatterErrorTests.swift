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
}
