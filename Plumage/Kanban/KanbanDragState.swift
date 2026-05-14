import CoreGraphics
import Foundation

nonisolated enum DragStatus: Sendable, Equatable {
    case lifting
    case dragging
    case dropping
    case cancelling
}

nonisolated struct ResolvedDropTarget: Equatable, Sendable {
    let column: IssueColumn
    let target: ProjectKanbanModel.DropTarget
    let insertionFrame: CGRect
}

nonisolated struct KanbanDragState: Equatable, Sendable {
    let payload: IssueDragPayload
    let sourceFolderName: String
    let sourceFrame: CGRect
    var cursorLocation: CGPoint
    var translation: CGSize
    var target: ResolvedDropTarget?
    var status: DragStatus
}

nonisolated func resolveDropTarget(
    cursor: CGPoint,
    cardFrames: [String: CGRect],
    columnFrames: [IssueColumn: CGRect],
    sortedIssues: [IssueColumn: [DiscoveredIssue]],
    sourceFolderName: String
) -> ResolvedDropTarget? {
    guard let column = columnFrames.first(where: { $0.value.contains(cursor) })?.key
    else { return nil }

    let cards = (sortedIssues[column] ?? [])
        .filter { $0.id != sourceFolderName }

    if cards.isEmpty {
        return ResolvedDropTarget(
            column: column,
            target: .column(column),
            insertionFrame: columnFrames[column] ?? .zero
        )
    }

    for card in cards {
        guard let frame = cardFrames[card.id] else { continue }
        if cursor.y < frame.midY {
            return ResolvedDropTarget(
                column: column,
                target: .aboveCard(folderName: card.id, column: column),
                insertionFrame: frame
            )
        }
    }
    let last = cards[cards.count - 1]
    let lastFrame = cardFrames[last.id] ?? .zero
    return ResolvedDropTarget(
        column: column,
        target: .belowCard(folderName: last.id, column: column),
        insertionFrame: lastFrame
    )
}
