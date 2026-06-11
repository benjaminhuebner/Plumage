import CoreGraphics
import Foundation
import Testing

@testable import Plumage

@Suite("resolveDropTarget")
struct ResolveDropTargetTests {
    @Test("cursor above a card-top in same column returns aboveCard")
    func cursorAboveCardTop() {
        let cards = [
            makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10),
            makeIssue(id: 2, folder: "00002-b", status: .approved, order: 20),
        ]
        let cardFrames: [String: CGRect] = [
            "00001-a": CGRect(x: 0, y: 0, width: 240, height: 100),
            "00002-b": CGRect(x: 0, y: 110, width: 240, height: 100),
        ]
        let columnFrames: [IssueColumn: CGRect] = [
            .todo: CGRect(x: 0, y: 0, width: 240, height: 600)
        ]
        let resolved = resolveDropTarget(
            cursor: CGPoint(x: 100, y: 130),
            cardFrames: cardFrames,
            columnFrames: columnFrames,
            sortedIssues: [.todo: cards.map { .valid($0) }],
            sourceFolderName: "ghost-source"
        )
        #expect(resolved?.column == .todo)
        #expect(resolved?.target == .aboveCard(folderName: "00002-b", column: .todo))
    }

    @Test("cursor past last card-mid returns belowCard for last card")
    func cursorBelowLast() {
        let cards = [
            makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10),
            makeIssue(id: 2, folder: "00002-b", status: .approved, order: 20),
        ]
        let cardFrames: [String: CGRect] = [
            "00001-a": CGRect(x: 0, y: 0, width: 240, height: 100),
            "00002-b": CGRect(x: 0, y: 110, width: 240, height: 100),
        ]
        let columnFrames: [IssueColumn: CGRect] = [
            .todo: CGRect(x: 0, y: 0, width: 240, height: 600)
        ]
        let resolved = resolveDropTarget(
            cursor: CGPoint(x: 100, y: 500),
            cardFrames: cardFrames,
            columnFrames: columnFrames,
            sortedIssues: [.todo: cards.map { .valid($0) }],
            sourceFolderName: "ghost-source"
        )
        #expect(resolved?.target == .belowCard(folderName: "00002-b", column: .todo))
    }

    @Test("cursor in empty column returns column-target")
    func cursorInEmptyColumn() {
        let columnFrames: [IssueColumn: CGRect] = [
            .done: CGRect(x: 260, y: 0, width: 240, height: 600)
        ]
        let resolved = resolveDropTarget(
            cursor: CGPoint(x: 300, y: 300),
            cardFrames: [:],
            columnFrames: columnFrames,
            sortedIssues: [:],
            sourceFolderName: "00001-a"
        )
        #expect(resolved?.column == .done)
        #expect(resolved?.target == .column(.done))
    }

    @Test("cursor between columns returns nil")
    func cursorBetweenColumns() {
        let columnFrames: [IssueColumn: CGRect] = [
            .todo: CGRect(x: 0, y: 0, width: 240, height: 600),
            .done: CGRect(x: 260, y: 0, width: 240, height: 600),
        ]
        let resolved = resolveDropTarget(
            cursor: CGPoint(x: 250, y: 300),
            cardFrames: [:],
            columnFrames: columnFrames,
            sortedIssues: [.todo: [], .done: []],
            sourceFolderName: "00001-a"
        )
        #expect(resolved == nil)
    }

    @Test("source card is excluded from resolution candidates")
    func sourceCardExcluded() {
        let cards = [
            makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10),
            makeIssue(id: 2, folder: "00002-b", status: .approved, order: 20),
        ]
        let cardFrames: [String: CGRect] = [
            "00001-a": CGRect(x: 0, y: 0, width: 240, height: 100),
            "00002-b": CGRect(x: 0, y: 110, width: 240, height: 100),
        ]
        let columnFrames: [IssueColumn: CGRect] = [
            .todo: CGRect(x: 0, y: 0, width: 240, height: 600)
        ]
        let resolved = resolveDropTarget(
            cursor: CGPoint(x: 100, y: 30),
            cardFrames: cardFrames,
            columnFrames: columnFrames,
            sortedIssues: [.todo: cards.map { .valid($0) }],
            sourceFolderName: "00001-a"
        )
        #expect(resolved?.target == .aboveCard(folderName: "00002-b", column: .todo))
    }

    @Test("cursor over source column with only source card returns column-target")
    func cursorOverSourceOnlyColumn() {
        let cards = [
            makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10)
        ]
        let columnFrames: [IssueColumn: CGRect] = [
            .todo: CGRect(x: 0, y: 0, width: 240, height: 600)
        ]
        let resolved = resolveDropTarget(
            cursor: CGPoint(x: 100, y: 200),
            cardFrames: ["00001-a": CGRect(x: 0, y: 0, width: 240, height: 100)],
            columnFrames: columnFrames,
            sortedIssues: [.todo: cards.map { .valid($0) }],
            sourceFolderName: "00001-a"
        )
        #expect(resolved?.target == .column(.todo))
    }

    @Test("empty cardFrames (initial state) returns column-target when in column")
    func emptyFramesFallsThrough() {
        let cards = [
            makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10)
        ]
        let columnFrames: [IssueColumn: CGRect] = [
            .todo: CGRect(x: 0, y: 0, width: 240, height: 600)
        ]
        let resolved = resolveDropTarget(
            cursor: CGPoint(x: 100, y: 200),
            cardFrames: [:],
            columnFrames: columnFrames,
            sortedIssues: [.todo: cards.map { .valid($0) }],
            sourceFolderName: "ghost-source"
        )
        #expect(resolved?.target == .belowCard(folderName: "00001-a", column: .todo))
    }

    private func makeIssue(
        id: Int,
        folder: String,
        status: IssueStatus,
        order: Double? = nil
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: "t",
            type: .feature, status: status,
            created: .distantPast, updated: .distantPast,
            branch: "issue/\(folder)", labels: [], order: order
        )
    }
}
