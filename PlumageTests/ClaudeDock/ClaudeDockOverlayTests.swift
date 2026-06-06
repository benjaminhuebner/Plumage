import SwiftUI
import Testing

@testable import Plumage

@MainActor
struct ClaudeDockOverlayTests {
    private func makeSession() -> ClaudeSession {
        ClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            stateDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("plumage-dock-tests-\(UUID().uuidString)"),
            autoSpawn: false
        )
    }

    @Test("toggle flips binding from false to true")
    func toggleFlipsBindingFromFalseToTrue() {
        var isOpen = false
        let binding = Binding<Bool>(
            get: { isOpen },
            set: { isOpen = $0 }
        )
        let overlay = ClaudeDockOverlay(
            session: makeSession(),
            indicatorState: .loading,
            isOpen: binding
        )
        overlay.toggle()
        #expect(isOpen == true)
    }

    @Test("toggle flips binding from true to false")
    func toggleFlipsBindingFromTrueToFalse() {
        var isOpen = true
        let binding = Binding<Bool>(
            get: { isOpen },
            set: { isOpen = $0 }
        )
        let overlay = ClaudeDockOverlay(
            session: makeSession(),
            indicatorState: .loading,
            isOpen: binding
        )
        overlay.toggle()
        #expect(isOpen == false)
    }
}
