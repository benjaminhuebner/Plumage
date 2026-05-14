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

// Flat properties so Observation invalidates narrowly: cursor moves only
// invalidate cursor/translation readers, not isActive/target/sourceFolderName.
// Storing the drag as a single `KanbanDragState?` causes every reader of
// `state` (e.g. `.scrollDisabled(state != nil)`, columns reading
// `state?.sourceFolderName`) to re-evaluate on every cursor frame, which
// cascades into the full KanbanView body and stalls the gesture.
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
            return ResolvedDropTarget(
                column: column,
                target: .aboveCard(folderName: card.id, column: column),
                insertionFrame: frame
            )
        }
    }
    let last = cards[cards.count - 1]
    let lastFrame = cardFrames[last.id] ?? .zero
    // Source's new position is BELOW lastFrame, not at lastFrame. Without
    // the +height shift, the drop animation lands at the wrong row and the
    // user sees "first below, then plopp" as the source's real layout slot
    // resolves a frame later.
    let insertionFrame = CGRect(
        origin: CGPoint(x: lastFrame.minX, y: lastFrame.maxY + 8),
        size: lastFrame.size
    )
    return ResolvedDropTarget(
        column: column,
        target: .belowCard(folderName: last.id, column: column),
        insertionFrame: insertionFrame
    )
}
