import Foundation
import Testing

@testable import Plumage

@Suite("ReviewFinding.reviewFixTaskText")
struct ReviewFixTaskTextTests {
    private static func finding(
        side: ReviewFinding.Side, lineText: String, comment: String = "Rename this"
    ) -> ReviewFinding {
        ReviewFinding(
            id: UUID(),
            file: "Sources/App.swift",
            side: side,
            line: 12,
            lineText: lineText,
            comment: comment,
            state: .open,
            round: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("new-side finding quotes the trimmed line")
    func newSide() {
        let text = Self.finding(side: .new, lineText: "    let answer = 42").reviewFixTaskText
        #expect(text == "Review fix: Sources/App.swift:12 — Rename this (line: `let answer = 42`)")
    }

    @Test("old-side finding is marked removed")
    func oldSide() {
        let text = Self.finding(side: .old, lineText: "let gone = true").reviewFixTaskText
        #expect(
            text
                == "Review fix: Sources/App.swift:12 (removed) — Rename this (line: `let gone = true`)"
        )
    }

    @Test("blank line text drops the quote suffix")
    func blankLine() {
        let text = Self.finding(side: .new, lineText: "   ").reviewFixTaskText
        #expect(text == "Review fix: Sources/App.swift:12 — Rename this")
    }
}
