import Testing

@testable import Plumage

@Suite("SideBySideAnchors")
struct SideBySideAnchorTests {
    @Test("a removed/added pair anchors old side left, new side right")
    func pairedRow() {
        let row = SideBySideRow(
            old: SideBySideCell(line: Line(kind: .removed, content: "old"), number: 12),
            new: SideBySideCell(line: Line(kind: .added, content: "new"), number: 34)
        )
        let anchors = DiffLineAnchor.anchors(for: row, file: "a.swift")
        #expect(anchors.old == DiffLineAnchor(file: "a.swift", side: .old, line: 12))
        #expect(anchors.new == DiffLineAnchor(file: "a.swift", side: .new, line: 34))
    }

    @Test("a context row targets one shared new-side anchor from both panes")
    func contextRow() {
        let line = Line(kind: .context, content: "same")
        let row = SideBySideRow(
            old: SideBySideCell(line: line, number: 12),
            new: SideBySideCell(line: line, number: 34)
        )
        let anchors = DiffLineAnchor.anchors(for: row, file: "a.swift")
        let expected = DiffLineAnchor(file: "a.swift", side: .new, line: 34)
        #expect(anchors.old == expected)
        #expect(anchors.new == expected)
    }

    @Test("an unpaired addition has no old-side anchor")
    func additionOnly() {
        let row = SideBySideRow(
            old: nil,
            new: SideBySideCell(line: Line(kind: .added, content: "new"), number: 7)
        )
        let anchors = DiffLineAnchor.anchors(for: row, file: "a.swift")
        #expect(anchors.old == nil)
        #expect(anchors.new == DiffLineAnchor(file: "a.swift", side: .new, line: 7))
    }

    @Test("an unpaired removal has no new-side anchor")
    func removalOnly() {
        let row = SideBySideRow(
            old: SideBySideCell(line: Line(kind: .removed, content: "old"), number: 9),
            new: nil
        )
        let anchors = DiffLineAnchor.anchors(for: row, file: "a.swift")
        #expect(anchors.old == DiffLineAnchor(file: "a.swift", side: .old, line: 9))
        #expect(anchors.new == nil)
    }

    @Test("side-by-side anchors agree with unified anchors for the same hunk")
    func agreesWithUnified() {
        let hunk = Hunk(
            oldStart: 10, oldCount: 3, newStart: 20, newCount: 3,
            lines: [
                Line(kind: .context, content: "ctx"),
                Line(kind: .removed, content: "gone"),
                Line(kind: .added, content: "here"),
                Line(kind: .context, content: "tail"),
            ]
        )
        let unified = DiffLineAnchor.anchors(for: hunk, file: "a.swift")
        let rows = SideBySideLayout.rows(for: hunk)
        let sideBySide = rows.map { DiffLineAnchor.anchors(for: $0, file: "a.swift") }
        #expect(sideBySide[0].new == unified[0])
        #expect(sideBySide[1].old == unified[1])
        #expect(sideBySide[1].new == unified[2])
        #expect(sideBySide[2].new == unified[3])
    }
}
