import Foundation
import Testing

@testable import Plumage

@Suite("SpecParser.extractGoal")
struct SpecParserGoalTests {
    @Test("normal Goal block returns the first paragraph trimmed")
    func normalGoal() {
        let content = """
            ---
            id: 1
            ---

            # Issue 1

            ## Context

            Some context here.

            ## Goal

            Make the kanban look polished and inviting.

            ## Scope
            """
        #expect(
            SpecParser.extractGoal(from: content)
                == "Make the kanban look polished and inviting."
        )
    }

    @Test("# Goal (H1) heading is accepted in addition to ## Goal")
    func acceptsH1GoalHeading() {
        let content = """
            ---
            id: 1
            ---

            # Goal

            H1 variant should work too.

            ## Scope
            """
        #expect(SpecParser.extractGoal(from: content) == "H1 variant should work too.")
    }

    @Test("missing Goal section returns nil")
    func missingGoal() {
        let content = """
            ---
            id: 1
            ---

            ## Context

            Some text.

            ## Scope
            """
        #expect(SpecParser.extractGoal(from: content) == nil)
    }

    @Test("Goal containing only an HTML comment returns nil")
    func htmlCommentOnly() {
        let content = """
            ---
            id: 1
            ---

            ## Goal

            <!-- One sentence. Why this issue exists, not what it does. -->

            ## Scope
            """
        #expect(SpecParser.extractGoal(from: content) == nil)
    }

    @Test("Goal with multiple paragraphs returns only the first")
    func multipleParagraphs() {
        let content = """
            ---
            id: 1
            ---

            ## Goal

            First paragraph here.

            Second paragraph that should be ignored.

            ## Scope
            """
        #expect(SpecParser.extractGoal(from: content) == "First paragraph here.")
    }

    @Test("Goal exactly 240 chars is not capped")
    func exactBoundaryNoCap() throws {
        let exact = String(repeating: "a", count: 240)
        let content = """
            ---
            id: 1
            ---

            ## Goal

            \(exact)

            ## Scope
            """
        let goal = try #require(SpecParser.extractGoal(from: content))
        #expect(goal == exact)
        #expect(!goal.hasSuffix("…"))
    }

    @Test("Goal longer than 240 chars is capped with ellipsis")
    func capsLongGoal() throws {
        let long = String(repeating: "a", count: 300)
        let content = """
            ---
            id: 1
            ---

            ## Goal

            \(long)

            ## Scope
            """
        let goal = try #require(SpecParser.extractGoal(from: content))
        #expect(goal.hasSuffix("…"))
        // 240 chars + ellipsis. Count is in Characters, not UTF-16 code units.
        #expect(goal.count == 241)
        #expect(goal.hasPrefix(String(repeating: "a", count: 240)))
    }

    @Test("unclosed HTML comment is preserved as literal text")
    func unclosedHTMLCommentPreserved() throws {
        let content = """
            ---
            id: 1
            ---

            ## Goal

            Real goal text. <!-- forgot to close

            ## Scope
            """
        let goal = try #require(SpecParser.extractGoal(from: content))
        #expect(goal.contains("Real goal text."))
        #expect(goal.contains("<!--"))
    }

    @Test("CRLF line endings are normalised before parsing")
    func crlfNormalised() {
        let content =
            "---\r\nid: 1\r\n---\r\n\r\n## Goal\r\n\r\nWindows line endings.\r\n\r\n## Scope\r\n"
        #expect(SpecParser.extractGoal(from: content) == "Windows line endings.")
    }

    @Test("Goal extraction strips inline HTML comments")
    func stripsInlineComment() {
        let content = """
            ---
            id: 1
            ---

            ## Goal

            Visible <!-- hidden --> text.

            ## Scope
            """
        #expect(SpecParser.extractGoal(from: content) == "Visible text.")
    }

    @Test("parse populates Issue.goal from the body")
    func parseExposesGoal() throws {
        let content = """
            ---
            id: 7
            title: t
            type: feature
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00007-x
            labels: []
            model: null
            ---

            # Issue

            ## Goal

            Short goal sentence.
            """
        guard case .success(let issue) = SpecParser.parse(content: content, folderName: "00007-x")
        else {
            Testing.Issue.record("expected success")
            return
        }
        #expect(issue.goal == "Short goal sentence.")
    }
}
