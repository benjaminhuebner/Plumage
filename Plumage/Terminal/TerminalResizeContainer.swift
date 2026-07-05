import AppKit

// SwiftTerm mutates buffer state inside setFrameSize — run synchronously inside
// AppKit's layout pass (sash drag) that trips Swift exclusivity. AppKit resizes
// only this container; the terminal frame is applied async per runloop turn.
final class TerminalResizeContainer: NSView {
    let terminalView: PersistentCursorTerminalView
    private var syncScheduled = false
    private var throttle = FrameSyncThrottle()
    private var trailingSyncTask: Task<Void, Never>?

    init(terminalView: PersistentCursorTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        // The frame sync lags layout by a runloop turn — never let a stale,
        // larger terminal paint past the visible pane in the meantime.
        clipsToBounds = true
        addSubview(terminalView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The terminal subtree must not feed sizes back into SwiftUI/Auto Layout:
    // fittingSize solves the translated constraints of SwiftTerm's subviews and
    // oscillates the inspector layout into an Update-Constraints runaway FAULT.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize { .zero }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleTerminalFrameSync()
    }

    override func layout() {
        super.layout()
        scheduleTerminalFrameSync()
    }

    private func scheduleTerminalFrameSync() {
        guard !syncScheduled else { return }
        syncScheduled = true
        Task { [weak self] in
            self?.applyTerminalFrameSync()
        }
    }

    func applyTerminalFrameSync(now: ContinuousClock.Instant = .now) {
        syncScheduled = false
        // A hidden/collapsing pane can momentarily report zero bounds — keep
        // the last real size instead of feeding a 0×0 SIGWINCH to the PTY.
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        guard terminalView.frame != bounds else { return }
        switch throttle.decide(now: now) {
        case .applyNow:
            trailingSyncTask?.cancel()
            trailingSyncTask = nil
            terminalView.frame = bounds
        case .deferTrailing:
            scheduleTrailingSync()
        }
    }

    // The trailing pass re-enters applyTerminalFrameSync after the gap so a
    // burst always ends on the final bounds — never on a stale mid-animation frame.
    private func scheduleTrailingSync() {
        guard trailingSyncTask == nil else { return }
        let gap = throttle.minimumGap
        trailingSyncTask = Task { [weak self] in
            try? await Task.sleep(for: gap)
            guard let self, !Task.isCancelled else { return }
            trailingSyncTask = nil
            applyTerminalFrameSync()
        }
    }
}
