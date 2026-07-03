import Testing

@testable import Plumage

@Suite("SideBySideLayout")
struct SideBySideLayoutTests {
    private static func hunk(_ kinds: [LineKind], oldStart: Int = 10, newStart: Int = 20) -> Hunk {
        let lines = kinds.enumerated().map { Line(kind: $0.element, content: "line \($0.offset)") }
        let oldCount = lines.count { $0.kind != .added }
        let newCount = lines.count { $0.kind != .removed }
        return Hunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            lines: lines
        )
    }

    @Test("context lines occupy both panes with independent numbering")
    func contextRows() throws {
        let rows = SideBySideLayout.rows(for: Self.hunk([.context, .context]))
        #expect(rows.count == 2)
        let first = try #require(rows.first)
        #expect(first.old?.line == first.new?.line)
        #expect(first.old?.number == 10)
        #expect(first.new?.number == 20)
        #expect(rows[1].old?.number == 11)
        #expect(rows[1].new?.number == 21)
    }

    @Test("paired removal/addition blocks share rows")
    func pairedRows() throws {
        let rows = SideBySideLayout.rows(for: Self.hunk([.removed, .removed, .added, .added]))
        try #require(rows.count == 2)
        #expect(rows[0].old?.line.content == "line 0")
        #expect(rows[0].new?.line.content == "line 2")
        #expect(rows[1].old?.line.content == "line 1")
        #expect(rows[1].new?.line.content == "line 3")
        #expect(rows[0].old?.number == 10)
        #expect(rows[0].new?.number == 20)
        #expect(rows[1].old?.number == 11)
        #expect(rows[1].new?.number == 21)
    }

    @Test("unequal blocks leave the remainder facing an empty cell")
    func unequalBlocks() throws {
        let rows = SideBySideLayout.rows(for: Self.hunk([.removed, .removed, .removed, .added]))
        try #require(rows.count == 3)
        #expect(rows[0].old != nil && rows[0].new != nil)
        #expect(rows[1].old != nil && rows[1].new == nil)
        #expect(rows[2].old != nil && rows[2].new == nil)
        #expect(rows[1].old?.number == 11)
        #expect(rows[2].old?.number == 12)
    }

    @Test("pure additions face an empty old cell")
    func pureAdditions() throws {
        let rows = SideBySideLayout.rows(for: Self.hunk([.context, .added, .added]))
        try #require(rows.count == 3)
        #expect(rows[1].old == nil)
        #expect(rows[2].old == nil)
        #expect(rows[1].new?.number == 21)
        #expect(rows[2].new?.number == 22)
    }

    @Test("pure removals face an empty new cell")
    func pureRemovals() throws {
        let rows = SideBySideLayout.rows(for: Self.hunk([.removed, .removed, .context]))
        try #require(rows.count == 3)
        #expect(rows[0].new == nil)
        #expect(rows[1].new == nil)
        #expect(rows[2].old?.number == 12)
        #expect(rows[2].new?.number == 20)
    }

    @Test("interleaved blocks keep pane numbering continuous")
    func interleavedBlocks() throws {
        let rows = SideBySideLayout.rows(
            for: Self.hunk([.context, .removed, .added, .context, .removed, .removed, .added])
        )
        try #require(rows.count == 5)
        #expect(rows[1].old?.line.content == "line 1")
        #expect(rows[1].new?.line.content == "line 2")
        #expect(rows[2].old?.number == 12)
        #expect(rows[2].new?.number == 22)
        #expect(rows[3].old?.line.content == "line 4")
        #expect(rows[3].new?.line.content == "line 6")
        #expect(rows[3].old?.number == 13)
        #expect(rows[3].new?.number == 23)
        #expect(rows[4].old?.line.content == "line 5")
        #expect(rows[4].new == nil)
    }

    @Test("row count never exceeds unified line count")
    func rowCountBounded() {
        let kinds: [LineKind] = [.context, .removed, .removed, .added, .context, .added]
        let rows = SideBySideLayout.rows(for: Self.hunk(kinds))
        #expect(rows.count <= kinds.count)
        let oldLines = rows.compactMap(\.old).count
        let newLines = rows.compactMap(\.new).count
        #expect(oldLines == kinds.count { $0 != .added })
        #expect(newLines == kinds.count { $0 != .removed })
    }

    @Test("column digits derive from hunk extents")
    func columnDigits() {
        let digits = SideBySideLayout.columnDigits(
            for: Hunk(oldStart: 95, oldCount: 10, newStart: 5, newCount: 3)
        )
        #expect(digits.old == 3)
        #expect(digits.new == 1)
    }
}
