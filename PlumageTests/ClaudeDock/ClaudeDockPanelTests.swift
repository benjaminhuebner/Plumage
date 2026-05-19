import SwiftUI
import Testing

@testable import Plumage

@MainActor
struct ClaudeDockPanelTests {
    @Test
    func panelHonoursSceneStorageDefault() {
        let session = ClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            autoSpawn: false
        )
        var isOpen = true
        let binding = Binding<Bool>(
            get: { isOpen },
            set: { isOpen = $0 }
        )
        let panel = ClaudeDockPanel(
            session: session,
            indicatorState: .loading,
            isOpen: binding
        )
        // The default mode is .chat — verified via the same SceneStorage
        // key used by the previous TerminalPaneView, so persistence carries
        // across the migration.
        #expect(panel.sceneStorageKeyForTesting == "terminalPaneMode")
        #expect(panel.defaultModeForTesting == .chat)
    }

    @Test
    func closeFlipsBindingToFalse() {
        let session = ClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            autoSpawn: false
        )
        var isOpen = true
        let binding = Binding<Bool>(
            get: { isOpen },
            set: { isOpen = $0 }
        )
        let panel = ClaudeDockPanel(
            session: session,
            indicatorState: .loading,
            isOpen: binding
        )
        panel.closeForTesting()
        #expect(isOpen == false)
    }

    @Test
    func terminalPaneModeRoundTrips() {
        #expect(TerminalPaneMode(rawValue: "chat") == .chat)
        #expect(TerminalPaneMode(rawValue: "terminal") == .terminal)
        #expect(TerminalPaneMode(rawValue: "garbage") == nil)
    }
}
