import Testing

@testable import Plumage

@Suite("SameNameMerge")
struct SameNameMergeTests {
    @Test("Fragments join in order with a thematic-break separator")
    func joinsInOrder() {
        let merged = SameNameMerge.mergeText(["# A\nfirst", "# B\nsecond"])
        #expect(merged == "# A\nfirst\n\n---\n\n# B\nsecond\n")
    }

    @Test("Surrounding whitespace is trimmed before joining")
    func trimsFragments() {
        let merged = SameNameMerge.mergeText(["\n\n  alpha  \n\n", "  beta\n"])
        #expect(merged == "alpha\n\n---\n\nbeta\n")
    }

    @Test("Blank fragments add no stray separator")
    func dropsBlanks() {
        let merged = SameNameMerge.mergeText(["only", "   ", "\n", "more"])
        #expect(merged == "only\n\n---\n\nmore\n")
    }

    @Test("A single fragment is returned with a trailing newline, no separator")
    func singleFragment() {
        #expect(SameNameMerge.mergeText(["solo"]) == "solo\n")
    }

    @Test("All-blank or empty input yields empty output")
    func emptyInput() {
        #expect(SameNameMerge.mergeText([]).isEmpty)
        #expect(SameNameMerge.mergeText(["", "  ", "\n"]).isEmpty)
    }
}
