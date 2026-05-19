import SwiftUI
import Testing

@testable import Plumage

@MainActor
struct ClaudeDockButtonTests {
    @Test("tap invokes the action closure")
    func tapInvokesAction() {
        var taps = 0
        let button = ClaudeDockButton(isOpen: false, isWorking: false) {
            taps += 1
        }
        button.action()
        #expect(taps == 1)
    }

    @Test("accessibility label reflects open state")
    func accessibilityLabelReflectsOpenState() {
        let closed = ClaudeDockButton(isOpen: false, isWorking: false) {}
        let open = ClaudeDockButton(isOpen: true, isWorking: false) {}
        #expect(closed.accessibilityLabelText == "Claude öffnen")
        #expect(open.accessibilityLabelText == "Claude schließen")
    }

    @Test("accessibility value reflects working state")
    func accessibilityValueReflectsWorkingState() {
        let idle = ClaudeDockButton(isOpen: false, isWorking: false) {}
        let working = ClaudeDockButton(isOpen: false, isWorking: true) {}
        #expect(idle.accessibilityValueText == "bereit")
        #expect(working.accessibilityValueText == "arbeitet")
    }

    @Test("symbol name is sparkles")
    func symbolNameIsSparkles() {
        #expect(ClaudeDockButton.symbolName == "sparkles")
    }
}
