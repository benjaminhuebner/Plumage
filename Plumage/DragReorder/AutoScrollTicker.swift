import CoreGraphics
import Foundation

nonisolated enum VerticalScrollEdge: Sendable, Equatable {
    case up
    case down
}

nonisolated enum AutoScrollMath {
    static let edgeZone: CGFloat = 10
    static let pointsPerSecond: CGFloat = 200
    static let tickIntervalMs: Int = 16
    static var tickDelta: CGFloat { pointsPerSecond * CGFloat(tickIntervalMs) / 1000.0 }

    static func verticalEdge(cursorY: CGFloat, in frame: CGRect) -> VerticalScrollEdge? {
        if cursorY < frame.minY + edgeZone { return .up }
        if cursorY > frame.maxY - edgeZone { return .down }
        return nil
    }
}

// The 60 Hz loop behind drag auto-scroll, owned by a surface-specific
// scroller that decides what each tick moves.
@MainActor
final class AutoScrollTicker {
    private var tickTask: Task<Void, Never>?

    func run(_ tick: @escaping @MainActor () -> Void) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                tick()
                // try (no `?`) so cancellation exits the loop on the same
                // tick rather than running one extra tick after stop().
                do {
                    try await Task.sleep(for: .milliseconds(AutoScrollMath.tickIntervalMs))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    // Safety net for abnormal teardown paths; primary cleanup remains the
    // owner's gesture-end → stop(). isolated deinit cancels the tick loop
    // immediately rather than letting `[weak self]` defer it by one tick.
    isolated deinit {
        tickTask?.cancel()
    }
}
