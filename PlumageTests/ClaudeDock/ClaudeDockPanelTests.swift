import SwiftUI
import Testing

@testable import Plumage

@MainActor
struct ClaudeDockPanelTests {
    private func makeSession() -> ClaudeSession {
        ClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            stateDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("plumage-dock-tests-\(UUID().uuidString)"),
            autoSpawn: false
        )
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
            indicatorState: .loading,
            isOpen: binding
        )
        panel.close()
        #expect(isOpen == false)
    }
}
