import Foundation
import Testing

@testable import Plumage

@Suite("DoneWhenMutator.transform")
struct DoneWhenMutatorTests {
    private let spec = """
        ---
        id: 7
        status: waiting-for-review
        updated: 2026-07-01T09:00:00Z
        ---

        # Title

        ## Tasks

        - [ ] a task, not a criterion

        ## Done when

        - [ ] first criterion
        - [x] second criterion

        ```
        - [ ] fenced decoy
        ```

        - [X] third criterion

        ## Notes

        - [ ] outside the section
        """

    @Test("ticking changes exactly the one checkbox character")
    func tickIsByteMinimal() throws {
        let output = try DoneWhenMutator.transform(content: spec, criterionIndex: 0, isChecked: true)
        let expected = spec.replacingOccurrences(
            of: "- [ ] first criterion", with: "- [x] first criterion")
        #expect(output == expected)
    }

    @Test("unticking changes exactly the one checkbox character")
    func untickIsByteMinimal() throws {
        let output = try DoneWhenMutator.transform(
            content: spec, criterionIndex: 1, isChecked: false)
        let expected = spec.replacingOccurrences(
            of: "- [x] second criterion", with: "- [ ] second criterion")
        #expect(output == expected)
    }

    @Test("uppercase X unticks and re-ticks as lowercase x")
    func uppercaseRoundTrip() throws {
        let unticked = try DoneWhenMutator.transform(
            content: spec, criterionIndex: 2, isChecked: false)
        #expect(unticked.contains("- [ ] third criterion"))
        let reticked = try DoneWhenMutator.transform(
            content: unticked, criterionIndex: 2, isChecked: true)
        #expect(reticked.contains("- [x] third criterion"))
        #expect(!reticked.contains("- [X] third criterion"))
    }

    @Test("already-matching state returns the content byte-identical")
    func idempotentNoChange() throws {
        let ticked = try DoneWhenMutator.transform(content: spec, criterionIndex: 1, isChecked: true)
        #expect(ticked == spec)
        let uppercase = try DoneWhenMutator.transform(
            content: spec, criterionIndex: 2, isChecked: true)
        #expect(uppercase == spec)
    }

    @Test("tick then untick restores the original bytes")
    func roundTrip() throws {
        let ticked = try DoneWhenMutator.transform(content: spec, criterionIndex: 0, isChecked: true)
        let restored = try DoneWhenMutator.transform(
            content: ticked, criterionIndex: 0, isChecked: false)
        #expect(restored == spec)
    }

    @Test("index counts only real criteria, skipping fenced decoys")
    func indexSkipsFencedDecoys() throws {
        let output = try DoneWhenMutator.transform(content: spec, criterionIndex: 2, isChecked: false)
        #expect(output.contains("- [ ] third criterion"))
        #expect(output.contains("- [ ] fenced decoy"))
    }

    @Test("task checkboxes and later sections stay untouched")
    func otherSectionsUntouched() throws {
        let output = try DoneWhenMutator.transform(content: spec, criterionIndex: 0, isChecked: true)
        #expect(output.contains("- [ ] a task, not a criterion"))
        #expect(output.contains("- [ ] outside the section"))
    }

    @Test("CRLF line endings survive the edit")
    func crlfPreserved() throws {
        let crlfSpec = spec.replacingOccurrences(of: "\n", with: "\r\n")
        let output = try DoneWhenMutator.transform(
            content: crlfSpec, criterionIndex: 0, isChecked: true)
        let expected = crlfSpec.replacingOccurrences(
            of: "- [ ] first criterion", with: "- [x] first criterion")
        #expect(output == expected)
    }

    @Test("out-of-range index throws criterionNotFound")
    func outOfRangeThrows() {
        #expect(throws: DoneWhenMutatorError.criterionNotFound(index: 3)) {
            try DoneWhenMutator.transform(content: spec, criterionIndex: 3, isChecked: true)
        }
        #expect(throws: DoneWhenMutatorError.criterionNotFound(index: -1)) {
            try DoneWhenMutator.transform(content: spec, criterionIndex: -1, isChecked: true)
        }
    }

    @Test("missing section throws for any index")
    func missingSectionThrows() {
        #expect(throws: DoneWhenMutatorError.criterionNotFound(index: 0)) {
            try DoneWhenMutator.transform(content: "# Title\n", criterionIndex: 0, isChecked: true)
        }
    }
}
