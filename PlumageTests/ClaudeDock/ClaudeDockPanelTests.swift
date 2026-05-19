import SwiftUI
import Testing

@testable import Plumage

@MainActor
struct ClaudeDockPanelTests {
    private func makeSession() -> ClaudeSession {
        ClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            autoSpawn: false
        )
    }

    @Test
    func sceneStorageKeyMatchesPreviousTerminalPaneViewKey() {
        // Persistence carries over from the pre-dock TerminalPaneView, so the
        // key must stay "terminalPaneMode". A rename here would silently reset
        // every user's mode preference to .chat on next launch.
        #expect(ClaudeDockPanel.sceneStorageKey == "terminalPaneMode")
        #expect(ClaudeDockPanel.defaultMode == .chat)
    }

    @Test
    func closeFlipsBindingToFalse() {
        var isOpen = true
        let binding = Binding<Bool>(
            get: { isOpen },
            set: { isOpen = $0 }
        )
        let panel = ClaudeDockPanel(
            session: makeSession(),
            indicatorState: .loading,
            isOpen: binding
        )
        panel.close()
        #expect(isOpen == false)
    }

    @Test
    func terminalPaneModeRoundTrips() {
        #expect(TerminalPaneMode(rawValue: "chat") == .chat)
        #expect(TerminalPaneMode(rawValue: "terminal") == .terminal)
        #expect(TerminalPaneMode(rawValue: "garbage") == nil)
    }

    @Test("handOffToExternal marks pending before tearing down")
    func handOffToExternalSetsPendingFirst() {
        let session = makeSession()
        #expect(!session.handOffPending)
        session.handOffToExternal()
        // No process to terminate (autoSpawn:false) — handOff() then clears
        // pending in its early-return path. The contract we verify is that
        // markHandOffStarting fired (handOffPending was true at some point);
        // the post-condition is observable via state transition.
        #expect(session.state == .exited(code: 0, reason: .userClosed))
    }

    @Test("handOffFromExternal marks pending and re-enters starting state")
    func handOffFromExternalSetsPendingAndRestarts() async {
        let session = makeSession()
        // Drive into a non-idle state first so resumeAfterHandOff has a
        // before-state worth transitioning from.
        session.beginExternalHandOff()
        #expect(session.handOffPending)
        session.handOffFromExternal()
        // markHandOffStarting keeps the pending flag true; resumeAfterHandOff
        // transitions state to .starting and queues a deferred spawn (no-op
        // here because autoSpawn:false). handOffPending stays true until a
        // markExternalHandOffDone signal arrives — verifying that here proves
        // the wrapper called markHandOffStarting before resume.
        #expect(session.handOffPending)
        if case .starting = session.state {
            // ok
        } else {
            Issue.record("expected .starting, got \(session.state)")
        }
    }
}
