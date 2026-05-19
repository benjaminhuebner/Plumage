import SwiftUI
import Testing

@testable import Plumage

@MainActor
struct ClaudeDockOverlayTests {
    private func makeSession() -> ClaudeSession {
        ClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            autoSpawn: false
        )
    }

    @Test
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
        overlay.toggleForTesting()
        #expect(isOpen == true)
    }

    @Test
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
        overlay.toggleForTesting()
        #expect(isOpen == false)
    }

    @Test
    func overlayRendersWithoutCrashingForBothStates() {
        var open = false
        let binding = Binding<Bool>(
            get: { open },
            set: { open = $0 }
        )
        let session = makeSession()
        _ =
            ClaudeDockOverlay(
                session: session,
                indicatorState: .loading,
                isOpen: binding
            ).body
        open = true
        _ =
            ClaudeDockOverlay(
                session: session,
                indicatorState: .loading,
                isOpen: binding
            ).body
    }
}
