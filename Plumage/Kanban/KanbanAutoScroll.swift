import CoreGraphics
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
    // One slot per IssueColumn. Adding a column then automatically gets
    // a backing position via the lazy default on read.
    var columnScrollPositions: [IssueColumn: ScrollPosition] = Dictionary(
        uniqueKeysWithValues: IssueColumn.allCases.map { ($0, ScrollPosition()) }
    )

    private(set) var activeTrigger: ScrollTrigger?
    private let ticker = AutoScrollTicker()

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
        guard let trigger = new else {
            ticker.stop()
            return
        }
        ticker.run { [weak self] in
            self?.tick(trigger: trigger)
        }
    }

    func stop() {
        ticker.stop()
        activeTrigger = nil
    }

    nonisolated static func detectTrigger(
        cursor: CGPoint,
        kanbanFrame: CGRect,
        columnFrames: [IssueColumn: CGRect]
    ) -> ScrollTrigger? {
        if cursor.x < kanbanFrame.minX + AutoScrollMath.edgeZone { return .kanbanLeft }
        if cursor.x > kanbanFrame.maxX - AutoScrollMath.edgeZone { return .kanbanRight }
        for (column, frame) in columnFrames where frame.contains(cursor) {
            switch AutoScrollMath.verticalEdge(cursorY: cursor.y, in: frame) {
            case .up: return .columnUp(column)
            case .down: return .columnDown(column)
            case nil: break
            }
        }
        return nil
    }

    private func tick(trigger: ScrollTrigger) {
        let delta = AutoScrollMath.tickDelta
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
        columnScrollPositions[column] ?? ScrollPosition()
    }

    func setColumnPosition(_ column: IssueColumn, to value: ScrollPosition) {
        columnScrollPositions[column] = value
    }

    // Produces a Binding rooted in `columnScrollPositions[column]` via the
    // get/set methods. Callers are expected to construct this once per
    // column (e.g. when building KanbanColumnView). Wrapping the dict
    // subscript by hand avoids the `Binding<ScrollPosition?>` shape that
    // `@Bindable`-projected dict subscripts produce.
    func columnBinding(for column: IssueColumn) -> Binding<ScrollPosition> {
        Binding(
            get: { [weak self] in self?.columnPosition(column) ?? ScrollPosition() },
            set: { [weak self] value in self?.setColumnPosition(column, to: value) }
        )
    }
}
