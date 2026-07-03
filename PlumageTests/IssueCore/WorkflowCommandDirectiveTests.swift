import Testing

@testable import Plumage

@Suite("WorkflowCommandDirective")
struct WorkflowCommandDirectiveTests {
    @Test("parses #if with tokens, tolerating leading whitespace and tabs")
    func parseOpen() {
        #expect(
            WorkflowCommandDirective.parse(line: "#if chore spike")
                == .open(tokens: ["chore", "spike"])
        )
        #expect(
            WorkflowCommandDirective.parse(line: "  \t#if\tfeature")
                == .open(tokens: ["feature"])
        )
        #expect(WorkflowCommandDirective.parse(line: "#if") == .open(tokens: []))
    }

    @Test("parses #end, consuming trailing junk tokens")
    func parseEnd() {
        #expect(WorkflowCommandDirective.parse(line: "#end") == .end)
        #expect(WorkflowCommandDirective.parse(line: "   #end junk") == .end)
    }

    @Test("parses #else, consuming trailing junk tokens")
    func parseElse() {
        #expect(WorkflowCommandDirective.parse(line: "#else") == .elseBranch)
        #expect(WorkflowCommandDirective.parse(line: " \t#else junk") == .elseBranch)
    }

    @Test("non-directive lines parse as nil")
    func parseNonDirective() {
        #expect(WorkflowCommandDirective.parse(line: "/plumage-plan <slug>") == nil)
        #expect(WorkflowCommandDirective.parse(line: "#ifx chore") == nil)
        #expect(WorkflowCommandDirective.parse(line: "#endless") == nil)
        #expect(WorkflowCommandDirective.parse(line: "#elsewhere") == nil)
        #expect(WorkflowCommandDirective.parse(line: "") == nil)
        #expect(WorkflowCommandDirective.parse(line: "   ") == nil)
    }

    @Test("matches is OR over tokens; unknown tokens, #else and #end match nothing")
    func matching() {
        let open = WorkflowCommandDirective.open(tokens: ["chore", "foobar"])
        #expect(open.matches(.chore))
        #expect(!open.matches(.feature))
        #expect(!WorkflowCommandDirective.open(tokens: []).matches(.chore))
        #expect(!WorkflowCommandDirective.end.matches(.chore))
        #expect(!WorkflowCommandDirective.elseBranch.matches(.chore))
    }

    @Test("bare #if matches no type and empty token list stays empty")
    func bareIf() {
        let bare = WorkflowCommandDirective.parse(line: "#if")
        for type in IssueType.allCases {
            #expect(bare?.matches(type) == false)
        }
    }
}
