import Foundation
import Testing

@testable import Plumage

@Suite("SpecTaskAppender")
struct SpecTaskAppenderTests {
    @Test("appends after the last task line, before the next section")
    func appendsInsideTasksSection() throws {
        let content = """
            # Title

            ## Tasks

            - [x] Done thing
            - [ ] Open thing

            ## Done when

            - [ ] Criterion
            """
        let result = try SpecTaskAppender.transform(
            content: content, taskTexts: ["Review fix: a.swift:3 — rename"])
        #expect(
            result == """
                # Title

                ## Tasks

                - [x] Done thing
                - [ ] Open thing
                - [ ] Review fix: a.swift:3 — rename

                ## Done when

                - [ ] Criterion
                """)
    }

    @Test("creates the section at the end when ## Tasks is missing")
    func createsMissingSection() throws {
        let content = """
            # Title

            ## Goal

            Something.
            """
        let result = try SpecTaskAppender.transform(content: content, taskTexts: ["Fix it"])
        #expect(
            result == """
                # Title

                ## Goal

                Something.

                ## Tasks

                - [ ] Fix it
                """)
    }

    @Test("preserves a trailing newline when creating the section")
    func preservesTrailingNewline() throws {
        let content = "# Title\n\n## Goal\n\nSomething.\n"
        let result = try SpecTaskAppender.transform(content: content, taskTexts: ["Fix it"])
        #expect(result == "# Title\n\n## Goal\n\nSomething.\n\n## Tasks\n\n- [ ] Fix it\n")
    }

    @Test("a fenced ## Tasks heading is not the section")
    func fencedHeaderIgnored() throws {
        let content = """
            # Title

            ```
            ## Tasks
            ```
            """
        let result = try SpecTaskAppender.transform(content: content, taskTexts: ["Fix it"])
        #expect(
            result == """
                # Title

                ```
                ## Tasks
                ```

                ## Tasks

                - [ ] Fix it
                """)
    }

    @Test("a fenced ## heading inside the section does not end it")
    func fencedHeadingInsideSection() throws {
        let content = """
            ## Tasks

            - [ ] Existing
            ```
            ## Done when
            - [ ] fake checkbox
            ```

            ## Done when
            """
        let result = try SpecTaskAppender.transform(content: content, taskTexts: ["New task"])
        #expect(
            result == """
                ## Tasks

                - [ ] Existing
                ```
                ## Done when
                - [ ] fake checkbox
                ```
                - [ ] New task

                ## Done when
                """)
    }

    @Test("empty section inserts directly under the header")
    func emptySection() throws {
        let content = """
            ## Tasks

            ## Done when
            """
        let result = try SpecTaskAppender.transform(content: content, taskTexts: ["Only task"])
        #expect(
            result == """
                ## Tasks
                - [ ] Only task

                ## Done when
                """)
    }

    @Test("preserves CRLF line endings")
    func preservesCRLF() throws {
        let content = "## Tasks\r\n\r\n- [ ] Existing\r\n\r\n## Done when\r\n"
        let result = try SpecTaskAppender.transform(content: content, taskTexts: ["New"])
        #expect(result == "## Tasks\r\n\r\n- [ ] Existing\r\n- [ ] New\r\n\r\n## Done when\r\n")
    }

    @Test("flattens newlines inside a task text")
    func flattensNewlines() throws {
        let content = "## Tasks\n\n- [ ] Existing\n"
        let result = try SpecTaskAppender.transform(
            content: content, taskTexts: ["multi\nline\ncomment"])
        #expect(result == "## Tasks\n\n- [ ] Existing\n- [ ] multi line comment\n")
    }

    @Test("empty task list throws")
    func emptyTaskListThrows() {
        #expect(throws: SpecTaskAppenderError.noTasksToAppend) {
            _ = try SpecTaskAppender.transform(content: "## Tasks\n", taskTexts: [])
        }
    }
}
