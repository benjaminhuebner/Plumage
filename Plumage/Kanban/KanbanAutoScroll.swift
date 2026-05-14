import CoreGraphics
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class KanbanAutoScroll {
    enum ScrollTrigger: Sendable, Equatable {
        case columnUp(IssueColumn)
        case columnDown(IssueColumn)
        case kanbanLeft
        case kanbanRight
    }

    var horizontalScroll = ScrollPosition()
    var todoScroll = ScrollPosition()
    var inProgressScroll = ScrollPosition()
    var waitingForReviewScroll = ScrollPosition()
    var doneScroll = ScrollPosition()

    private(set) var activeTrigger: ScrollTrigger?
    private var tickTask: Task<Void, Never>?

    nonisolated static let edgeZone: CGFloat = 10
    nonisolated static let pointsPerSecond: CGFloat = 200
    nonisolated static let tickIntervalMs: Int = 16

    func update(
        active: Bool,
        cursor: CGPoint,
        kanbanFrame: CGRect,
        columnFrames: [IssueColumn: CGRect]
    ) {
        guard active else {
            stop()
            return
        }
        let new = Self.detectTrigger(
            cursor: cursor, kanbanFrame: kanbanFrame, columnFrames: columnFrames)
        guard new != activeTrigger else { return }
        activeTrigger = new
        tickTask?.cancel()
        guard let trigger = new else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                self.tick(trigger: trigger)
                try? await Task.sleep(for: .milliseconds(Self.tickIntervalMs))
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        activeTrigger = nil
    }

    nonisolated static func detectTrigger(
        cursor: CGPoint,
        kanbanFrame: CGRect,
        columnFrames: [IssueColumn: CGRect]
    ) -> ScrollTrigger? {
        if cursor.x < kanbanFrame.minX + edgeZone { return .kanbanLeft }
        if cursor.x > kanbanFrame.maxX - edgeZone { return .kanbanRight }
        for (column, frame) in columnFrames where frame.contains(cursor) {
            if cursor.y < frame.minY + edgeZone { return .columnUp(column) }
            if cursor.y > frame.maxY - edgeZone { return .columnDown(column) }
        }
        return nil
    }

    private func tick(trigger: ScrollTrigger) {
        let delta = Self.pointsPerSecond * CGFloat(Self.tickIntervalMs) / 1000.0
        switch trigger {
        case .columnUp(let column):
            scrollColumn(column, dy: -delta)
        case .columnDown(let column):
            scrollColumn(column, dy: delta)
        case .kanbanLeft:
            scrollHorizontal(dx: -delta)
        case .kanbanRight:
            scrollHorizontal(dx: delta)
        }
    }

    private func scrollColumn(_ column: IssueColumn, dy: CGFloat) {
        var pos = columnPosition(column)
        let current = pos.point ?? .zero
        pos.scrollTo(point: CGPoint(x: current.x, y: max(0, current.y + dy)))
        setColumnPosition(column, to: pos)
    }

    private func scrollHorizontal(dx: CGFloat) {
        let current = horizontalScroll.point ?? .zero
        horizontalScroll.scrollTo(
            point: CGPoint(x: max(0, current.x + dx), y: current.y))
    }

    func columnPosition(_ column: IssueColumn) -> ScrollPosition {
        switch column {
        case .todo: todoScroll
        case .inProgress: inProgressScroll
        case .waitingForReview: waitingForReviewScroll
        case .done: doneScroll
        }
    }

    func setColumnPosition(_ column: IssueColumn, to value: ScrollPosition) {
        switch column {
        case .todo: todoScroll = value
        case .inProgress: inProgressScroll = value
        case .waitingForReview: waitingForReviewScroll = value
        case .done: doneScroll = value
        }
    }
}
