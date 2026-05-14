import CoreGraphics
import Foundation
import Observation
import SwiftUI

nonisolated enum KanbanAnimations {
    static let reducedDuration: Double = 0.05

    static func placeholder(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: reducedDuration) : .smooth(duration: 0.18)
    }

    static func drop(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: reducedDuration) : .easeOut(duration: 0.18)
    }

    static func cancel(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: reducedDuration) : .spring(response: 0.3, dampingFraction: 0.7)
    }
}

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

// Flat properties so Observation invalidates narrowly: a cursor move only
// invalidates cursor/translation readers, not isActive/target/sourceFolderName.
// A previous version stored the drag as a single `KanbanDragState?` and every
// reader of `state` re-evaluated on every cursor frame, cascading into the
// full KanbanView body and stalling the gesture.
@Observable
@MainActor
final class KanbanDragController {
    private(set) var isActive: Bool = false
    private(set) var payload: IssueDragPayload?
    private(set) var sourceFolderName: String?
    private(set) var sourceFrame: CGRect = .zero
    private(set) var cursorLocation: CGPoint = .zero
    private(set) var translation: CGSize = .zero
    private(set) var target: ResolvedDropTarget?
    private(set) var status: DragStatus = .lifting

    func startLift(payload: IssueDragPayload, sourceFolderName: String, sourceFrame: CGRect) {
        guard !isActive else { return }
        self.payload = payload
        self.sourceFolderName = sourceFolderName
        self.sourceFrame = sourceFrame
        self.cursorLocation = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        self.translation = .zero
        self.target = nil
        self.status = .lifting
        self.isActive = true
    }

    func updateCursor(location: CGPoint, translation: CGSize) {
        guard isActive else { return }
        self.cursorLocation = location
        self.translation = translation
        if status == .lifting {
            status = .dragging
        }
    }

    func setTarget(_ target: ResolvedDropTarget?) {
        guard isActive else { return }
        self.target = target
    }

    func beginDrop(finalTranslation: CGSize) {
        guard isActive else { return }
        status = .dropping
        translation = finalTranslation
    }

    func beginCancel() {
        guard isActive else { return }
        status = .cancelling
        translation = .zero
    }

    func clear() {
        isActive = false
        payload = nil
        sourceFolderName = nil
        target = nil
    }
}

nonisolated func computePlaceholderIndex(
    dragTarget: ProjectKanbanModel.DropTarget?,
    column: IssueColumn,
    visibleIssues: [DiscoveredIssue]
) -> Int? {
    guard let dragTarget else { return nil }
    switch dragTarget {
    case .column(let targetColumn):
        guard targetColumn == column else { return nil }
        return visibleIssues.count
    case .aboveCard(let folderName, let targetColumn):
        guard targetColumn == column else { return nil }
        return visibleIssues.firstIndex(where: { $0.id == folderName })
    case .belowCard(let folderName, let targetColumn):
        guard targetColumn == column else { return nil }
        guard let idx = visibleIssues.firstIndex(where: { $0.id == folderName }) else { return nil }
        return idx + 1
    }
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
            // insertionFrame must point at where the SOURCE actually lands
            // — the placeholder slot ABOVE the target card — not at the
            // target card's own frame. The placeholder is rendered before
            // the card with `KanbanLayout.cardSpacing` between them, so the
            // source's real layout slot is one card-height higher than the
            // matched card.
            let insertionFrame = CGRect(
                x: frame.minX,
                y: frame.minY - KanbanLayout.cardSpacing - KanbanLayout.cardHeight,
                width: frame.width,
                height: KanbanLayout.cardHeight
            )
            return ResolvedDropTarget(
                column: column,
                target: .aboveCard(folderName: card.id, column: column),
                insertionFrame: insertionFrame
            )
        }
    }
    let last = cards[cards.count - 1]
    let lastFrame = cardFrames[last.id] ?? .zero
    // Source's new position is BELOW lastFrame plus one spacing — the
    // placeholder slot for belowCard sits in that gap.
    let insertionFrame = CGRect(
        origin: CGPoint(x: lastFrame.minX, y: lastFrame.maxY + KanbanLayout.cardSpacing),
        size: CGSize(width: lastFrame.width, height: KanbanLayout.cardHeight)
    )
    return ResolvedDropTarget(
        column: column,
        target: .belowCard(folderName: last.id, column: column),
        insertionFrame: insertionFrame
    )
}
