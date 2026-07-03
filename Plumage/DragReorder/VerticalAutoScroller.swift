import CoreGraphics
import Observation
import SwiftUI

@Observable
@MainActor
final class VerticalAutoScroller {
    var position = ScrollPosition()
    private(set) var activeEdge: VerticalScrollEdge?
    private let ticker = AutoScrollTicker()

    func update(active: Bool, cursorY: CGFloat, frame: CGRect) {
        guard active else {
            stop()
            return
        }
        let edge = AutoScrollMath.verticalEdge(cursorY: cursorY, in: frame)
        guard edge != activeEdge else { return }
        activeEdge = edge
        guard let edge else {
            ticker.stop()
            return
        }
        ticker.run { [weak self] in
            self?.tick(edge: edge)
        }
    }

    func stop() {
        ticker.stop()
        activeEdge = nil
    }

    private func tick(edge: VerticalScrollEdge) {
        let delta = edge == .up ? -AutoScrollMath.tickDelta : AutoScrollMath.tickDelta
        let current = position.point ?? .zero
        position.scrollTo(point: CGPoint(x: current.x, y: max(0, current.y + delta)))
    }
}
