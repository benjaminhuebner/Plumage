import Foundation
import Testing

@testable import Plumage

@Suite("DoneWhenParser")
struct DoneWhenParserTests {
    @Test("mixed checked and unchecked criteria parse in order")
    func mixedCriteria() throws {
        let content = """
            ---
            id: 1
            ---

            # Title

            ## Done when

            - [ ] first criterion
            - [x] second criterion
            - [X] third criterion
            """
        let criteria = DoneWhenParser.criteria(in: content)
        #expect(
            criteria == [
                DoneWhenCriterion(text: "first criterion", isChecked: false),
                DoneWhenCriterion(text: "second criterion", isChecked: true),
                DoneWhenCriterion(text: "third criterion", isChecked: true),
            ])
    }

    @Test("missing section yields no criteria")
    func missingSection() {
        let content = """
            # Title

            ## Tasks

            - [ ] a task, not a criterion
            """
        #expect(DoneWhenParser.criteria(in: content).isEmpty)
    }

    @Test("checkbox lines inside code fences are ignored")
    func fencedDecoys() throws {
        let content = """
            ## Done when

            - [ ] real one

            ```
            - [ ] backtick decoy
            ```

            ~~~
            - [ ] tilde decoy
            ~~~

            - [ ] real two
            """
        let criteria = DoneWhenParser.criteria(in: content)
        #expect(criteria.map(\.text) == ["real one", "real two"])
    }

    @Test("mismatched fence markers do not close each other")
    func mismatchedFences() throws {
        let content = """
            ## Done when

            ```
            ~~~
            - [ ] still fenced
            ```

            - [ ] real
            """
        let criteria = DoneWhenParser.criteria(in: content)
        #expect(criteria.map(\.text) == ["real"])
    }

    @Test("section ends at the next H2 heading")
    func sectionEndsAtNextH2() throws {
        let content = """
            ## Done when

            - [ ] inside

            ## Notes

            - [ ] outside
            """
        let criteria = DoneWhenParser.criteria(in: content)
        #expect(criteria.map(\.text) == ["inside"])
    }

    @Test("an H3 sub-heading does not end the section")
    func h3DoesNotEndSection() throws {
        let content = """
            ## Done when

            - [ ] before sub

            ### Sub-criteria

            - [ ] after sub
            """
        let criteria = DoneWhenParser.criteria(in: content)
        #expect(criteria.map(\.text) == ["before sub", "after sub"])
    }

    @Test("indented checkbox lines are not criteria")
    func indentedNotCounted() {
        let content = """
            ## Done when

            - [ ] top level
              - [ ] nested
            """
        #expect(DoneWhenParser.criteria(in: content).map(\.text) == ["top level"])
    }

    @Test("CRLF content parses and line indices point at the normalized lines")
    func crlfContent() throws {
        let content = "## Done when\r\n\r\n- [ ] first\r\n- [x] second\r\n"
        let lines = DoneWhenParser.checkboxLines(in: content)
        #expect(lines.count == 2)
        #expect(lines[0].lineIndex == 2)
        #expect(lines[1].lineIndex == 3)
        #expect(lines[1].isChecked)
    }

    @Test("header requires an exact H2 title")
    func headerExactMatch() {
        let content = """
            ## Done whenever

            - [ ] not a criterion
            """
        #expect(DoneWhenParser.criteria(in: content).isEmpty)
    }

    @Test("checkbox without text keeps an empty label")
    func emptyLabel() throws {
        let content = """
            ## Done when

            - [ ]
            """
        let criteria = DoneWhenParser.criteria(in: content)
        #expect(criteria == [DoneWhenCriterion(text: "", isChecked: false)])
    }
}
