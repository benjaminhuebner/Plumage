import Foundation
import Testing

@testable import Plumage

@Suite("ReviewFindingStaleness")
struct ReviewFindingStalenessTests {
    private static func finding(
        file: String = "a.swift",
        side: ReviewFinding.Side = .new,
        line: Int = 3,
        lineText: String = "let x = 1"
    ) -> ReviewFinding {
        ReviewFinding(
            id: UUID(),
            file: file,
            side: side,
            line: line,
            lineText: lineText,
            comment: "c",
            state: .open,
            round: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func files(lines: [Line], path: String = "a.swift") -> [FileDiff] {
        [
            FileDiff(
                path: path,
                status: .modified,
                hunks: [Hunk(oldStart: 1, oldCount: 3, newStart: 1, newCount: 3, lines: lines)]
            )
        ]
    }

    @Test("finding whose line text still appears on its side is fresh")
    func freshWhenTextPresent() {
        let files = Self.files(lines: [Line(kind: .added, content: "let x = 1")])
        #expect(!ReviewFindingStaleness.isStale(Self.finding(side: .new), in: files))
    }

    @Test("finding is stale when the text vanished from the diff")
    func staleWhenTextGone() {
        let files = Self.files(lines: [Line(kind: .added, content: "let x = 2")])
        #expect(ReviewFindingStaleness.isStale(Self.finding(side: .new), in: files))
    }

    @Test("finding is stale when its file left the diff")
    func staleWhenFileGone() {
        let files = Self.files(lines: [Line(kind: .added, content: "let x = 1")], path: "b.swift")
        #expect(ReviewFindingStaleness.isStale(Self.finding(side: .new), in: files))
    }

    @Test("old-side finding matches removed lines but not added ones")
    func oldSideMatchesRemovedOnly() {
        let removed = Self.files(lines: [Line(kind: .removed, content: "let x = 1")])
        let added = Self.files(lines: [Line(kind: .added, content: "let x = 1")])
        #expect(!ReviewFindingStaleness.isStale(Self.finding(side: .old), in: removed))
        #expect(ReviewFindingStaleness.isStale(Self.finding(side: .old), in: added))
    }

    @Test("context lines satisfy both sides")
    func contextMatchesBothSides() {
        let files = Self.files(lines: [Line(kind: .context, content: "let x = 1")])
        #expect(!ReviewFindingStaleness.isStale(Self.finding(side: .new), in: files))
        #expect(!ReviewFindingStaleness.isStale(Self.finding(side: .old), in: files))
    }
}

@Suite("DiffLineAnchor")
struct DiffLineAnchorTests {
    @Test("anchors walk old and new numbers per line kind")
    func anchorNumbering() {
        let hunk = Hunk(
            oldStart: 10, oldCount: 3, newStart: 20, newCount: 4,
            lines: [
                Line(kind: .context, content: "a"),
                Line(kind: .removed, content: "b"),
                Line(kind: .added, content: "c"),
                Line(kind: .added, content: "d"),
                Line(kind: .context, content: "e"),
            ]
        )
        let anchors = DiffLineAnchor.anchors(for: hunk, file: "f.swift")
        #expect(
            anchors == [
                DiffLineAnchor(file: "f.swift", side: .new, line: 20),
                DiffLineAnchor(file: "f.swift", side: .old, line: 11),
                DiffLineAnchor(file: "f.swift", side: .new, line: 21),
                DiffLineAnchor(file: "f.swift", side: .new, line: 22),
                DiffLineAnchor(file: "f.swift", side: .new, line: 23),
            ])
    }
}
