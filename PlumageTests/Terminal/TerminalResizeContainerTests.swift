import AppKit
import Testing

@testable import Plumage

@MainActor
struct TerminalResizeContainerTests {
    @Test func frameSyncIsDeferredOutOfTheResizeCall() {
        let terminal = PersistentCursorTerminalView(frame: .zero)
        let container = TerminalResizeContainer(terminalView: terminal)

        container.setFrameSize(NSSize(width: 400, height: 300))

        // Synchronously the terminal must be untouched — applying inside the
        // resize call would put SwiftTerm back into the AppKit layout pass.
        #expect(terminal.frame.size == .zero)

        container.applyTerminalFrameSync()
        #expect(terminal.frame == container.bounds)
    }

    @Test func zeroSizeKeepsLastRealTerminalFrame() {
        let terminal = PersistentCursorTerminalView(frame: .zero)
        let container = TerminalResizeContainer(terminalView: terminal)

        container.setFrameSize(NSSize(width: 400, height: 300))
        container.applyTerminalFrameSync()
        let realFrame = terminal.frame

        container.setFrameSize(.zero)
        container.applyTerminalFrameSync()

        #expect(terminal.frame == realFrame)
    }

    @Test func rapidResizeBurstCoalescesToTrailingApply() {
        let terminal = PersistentCursorTerminalView(frame: .zero)
        let container = TerminalResizeContainer(terminalView: terminal)
        let start = ContinuousClock.now

        container.setFrameSize(NSSize(width: 400, height: 300))
        container.applyTerminalFrameSync(now: start)
        #expect(terminal.frame == container.bounds)

        // Mid-burst frames defer instead of reflowing the PTY per animation tick.
        container.setFrameSize(NSSize(width: 420, height: 300))
        container.applyTerminalFrameSync(now: start + .milliseconds(16))
        #expect(terminal.frame.width == 400)

        // Deterministic stand-in for the trailing task: past the gap the same
        // entry point applies the final bounds (the real task then no-ops).
        container.applyTerminalFrameSync(now: start + .milliseconds(200))
        #expect(terminal.frame == container.bounds)
    }

    @Test func scheduledSyncAppliesAfterRunLoopTurn() async throws {
        let terminal = PersistentCursorTerminalView(frame: .zero)
        let container = TerminalResizeContainer(terminalView: terminal)

        container.setFrameSize(NSSize(width: 500, height: 320))

        // The scheduled Task hops through the main actor — a short sleep lets
        // it run without racing the test.
        try await Task.sleep(for: .milliseconds(50))

        #expect(terminal.frame == container.bounds)
    }
}
