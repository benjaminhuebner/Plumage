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

    private func makeTerminalSession() -> TerminalClaudeSession {
        TerminalClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            sessionIDStoreOverride: FileManager.default.temporaryDirectory
                .appendingPathComponent("plumage-panel-tests-\(UUID().uuidString)")
        )
    }

    @Test("scene storage key matches previous TerminalPaneView key")
    func sceneStorageKeyMatchesPreviousTerminalPaneViewKey() {
        // Persistence carries over from the pre-dock TerminalPaneView, so the
        // key must stay "terminalPaneMode". A rename here would silently reset
        // every user's mode preference to .chat on next launch.
        #expect(ClaudeDockPanel.sceneStorageKey == "terminalPaneMode")
        #expect(ClaudeDockPanel.defaultMode == .chat)
    }

    @Test("close flips binding to false")
    func closeFlipsBindingToFalse() {
        var isOpen = true
        let binding = Binding<Bool>(
            get: { isOpen },
            set: { isOpen = $0 }
        )
        let panel = ClaudeDockPanel(
            session: makeSession(),
            terminalSession: makeTerminalSession(),
            indicatorState: .loading,
            isOpen: binding
        )
        panel.close()
        #expect(isOpen == false)
    }

    @Test("TerminalPaneMode raw value round-trips")
    func terminalPaneModeRoundTrips() {
        #expect(TerminalPaneMode(rawValue: "chat") == .chat)
        #expect(TerminalPaneMode(rawValue: "terminal") == .terminal)
        #expect(TerminalPaneMode(rawValue: "garbage") == nil)
    }
}
