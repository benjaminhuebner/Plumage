import Testing

@testable import Plumage

@Suite("WordDiffPass")
struct WordDiffPassTests {
    private static func changedTexts(of line: Line) -> [String]? {
        line.changedRanges.map { ranges in ranges.map { String(line.content[$0]) } }
    }

    @Test("paired lines carry the changed-token ranges")
    func pairedLinesEnriched() throws {
        let lines = [
            Line(kind: .context, content: "func run() {"),
            Line(kind: .removed, content: "    let count = 1"),
            Line(kind: .added, content: "    let count = 2"),
            Line(kind: .context, content: "}"),
        ]
        let enriched = WordDiffPass.enrich(lines)
        #expect(Self.changedTexts(of: enriched[1]) == ["1"])
        #expect(Self.changedTexts(of: enriched[2]) == ["2"])
        #expect(enriched[0].changedRanges == nil)
        #expect(enriched[3].changedRanges == nil)
    }

    @Test("unpaired lines stay without word-level information")
    func unpairedLinesUntouched() {
        let lines = [
            Line(kind: .added, content: "brand new line"),
            Line(kind: .context, content: "unchanged"),
        ]
        let enriched = WordDiffPass.enrich(lines)
        #expect(enriched.allSatisfy { $0.changedRanges == nil })
        #expect(enriched == lines)
    }

    @Test("unequal blocks enrich only the paired overlap")
    func unequalBlocks() throws {
        let lines = [
            Line(kind: .removed, content: "alpha one"),
            Line(kind: .removed, content: "beta two"),
            Line(kind: .added, content: "alpha 1"),
        ]
        let enriched = WordDiffPass.enrich(lines)
        #expect(Self.changedTexts(of: enriched[0]) == ["one"])
        #expect(Self.changedTexts(of: enriched[2]) == ["1"])
        #expect(enriched[1].changedRanges == nil)
    }

    @Test("classifier cap leaves paired lines at whole-line fallback")
    func capFallback() {
        let long = String(repeating: "a ", count: 5000)
        let lines = [
            Line(kind: .removed, content: long + "x"),
            Line(kind: .added, content: long + "y"),
        ]
        let enriched = WordDiffPass.enrich(lines)
        #expect(enriched.allSatisfy { $0.changedRanges == nil })
    }

    @Test("tokens and trailing-newline flags survive enrichment")
    func metadataPreserved() throws {
        let removed = Line(kind: .removed, content: "value", hasNoTrailingNewline: true)
        let added = Line(kind: .added, content: "walue", hasNoTrailingNewline: true)
        let enriched = WordDiffPass.enrich([removed, added])
        #expect(enriched[0].hasNoTrailingNewline)
        #expect(enriched[1].hasNoTrailingNewline)
        #expect(Self.changedTexts(of: enriched[0]) == ["value"])
        #expect(Self.changedTexts(of: enriched[1]) == ["walue"])
    }

    @Test("parser output carries word-diff ranges for paired hunk lines")
    func parserIntegration() throws {
        let diff = """
            diff --git a/sample.swift b/sample.swift
            index 1111111..2222222 100644
            --- a/sample.swift
            +++ b/sample.swift
            @@ -1,3 +1,3 @@
             let unchanged = true
            -let value = 1
            +let value = 2
            """
        let files = DiffParser.parse(unifiedDiff: diff)
        let hunk = try #require(files.first?.hunks.first)
        let removed = try #require(hunk.lines.first { $0.kind == .removed })
        let added = try #require(hunk.lines.first { $0.kind == .added })
        #expect(Self.changedTexts(of: removed) == ["1"])
        #expect(Self.changedTexts(of: added) == ["2"])
    }
}
