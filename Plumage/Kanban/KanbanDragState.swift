import CoreGraphics
import Foundation
import Observation
import SwiftUI

nonisolated enum KanbanAnimations {
    static let reducedDuration: Double = 0.05

    static func lift(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: reducedDuration) : .spring(response: 0.22, dampingFraction: 0.7)
    }

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

nonisolated struct KanbanDragState: Equatable, Sendable {
    let payload: IssueDragPayload
    let sourceFolderName: String
    let sourceFrame: CGRect
    var cursorLocation: CGPoint
    var translation: CGSize
    var target: ResolvedDropTarget?
    var status: DragStatus
}

@Observable
@MainActor
final class KanbanDragController {
    private(set) var state: KanbanDragState?

    func startLift(payload: IssueDragPayload, sourceFolderName: String, sourceFrame: CGRect) {
        guard state == nil else { return }
        state = KanbanDragState(
            payload: payload,
            sourceFolderName: sourceFolderName,
            sourceFrame: sourceFrame,
            cursorLocation: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
            translation: .zero,
            target: nil,
            status: .lifting
        )
    }

    func updateCursor(location: CGPoint, translation: CGSize) {
        guard var current = state else { return }
        current.cursorLocation = location
        current.translation = translation
        if current.status == .lifting {
            current.status = .dragging
        }
        state = current
    }

    func setTarget(_ target: ResolvedDropTarget?) {
        guard var current = state else { return }
        current.target = target
        state = current
    }

    func beginDrop(finalTranslation: CGSize) {
        guard var current = state else { return }
        current.status = .dropping
        current.translation = finalTranslation
        state = current
    }

    func beginCancel() {
        guard var current = state else { return }
        current.status = .cancelling
        current.translation = .zero
        state = current
    }

    func clear() {
        state = nil
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
