import Foundation

// Column animations resize the terminal every frame; each cell-boundary
// crossing costs a PTY SIGWINCH and a full TUI repaint. Bursts coalesce to a
// trailing apply so claude reflows a few times per animation, not per frame.
nonisolated struct FrameSyncThrottle {
    enum Decision: Equatable {
        case applyNow
        case deferTrailing
    }

    let minimumGap: Duration
    private(set) var lastApply: ContinuousClock.Instant?

    // 50 ms: tight enough that the pane edge tracks a sash drag, long enough
    // to cut a 250 ms column animation from ~15 PTY reflows to ~5.
    init(minimumGap: Duration = .milliseconds(50)) {
        self.minimumGap = minimumGap
    }

    mutating func decide(now: ContinuousClock.Instant) -> Decision {
        if let lastApply, now - lastApply < minimumGap {
            return .deferTrailing
        }
        lastApply = now
        return .applyNow
    }
}
