import SwiftUI
import Testing

@testable import Plumage

@MainActor
struct ClaudeDockButtonTests {
    @Test
    func tapInvokesAction() {
        var taps = 0
        let button = ClaudeDockButton(isOpen: false, isWorking: false) {
            taps += 1
        }
        // The closure is the only behavioral surface the view exposes
        // without a UI test host; calling it directly verifies the wiring.
        _ = button.body
        button.invokeForTesting()
        #expect(taps == 1)
    }

    @Test
    func accessibilityLabelReflectsOpenState() {
        let closed = ClaudeDockButton(isOpen: false, isWorking: false) {}
        let open = ClaudeDockButton(isOpen: true, isWorking: false) {}
        #expect(closed.accessibilityLabelForTesting == "Claude öffnen")
        #expect(open.accessibilityLabelForTesting == "Claude schließen")
    }

    @Test
    func accessibilityValueReflectsWorkingState() {
        let idle = ClaudeDockButton(isOpen: false, isWorking: false) {}
        let working = ClaudeDockButton(isOpen: false, isWorking: true) {}
        #expect(idle.accessibilityValueForTesting == "bereit")
        #expect(working.accessibilityValueForTesting == "arbeitet")
    }

    @Test
    func symbolNameIsSparkles() {
        #expect(ClaudeDockButton.symbolName == "sparkles")
    }
}
