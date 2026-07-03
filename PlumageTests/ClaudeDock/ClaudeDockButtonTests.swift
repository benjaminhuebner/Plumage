import Testing

@testable import Plumage

@MainActor
struct ClaudeDockButtonTests {
    @Test("tap invokes the action closure")
    func tapInvokesAction() {
        var taps = 0
        let button = ClaudeDockButton(isWorking: false) {
            taps += 1
        }
        button.action()
        #expect(taps == 1)
    }

    @Test("accessibility value reflects working state")
    func accessibilityValueReflectsWorkingState() {
        let idle = ClaudeDockButton(isWorking: false) {}
        let working = ClaudeDockButton(isWorking: true) {}
        #expect(idle.accessibilityValueText == "Ready")
        #expect(working.accessibilityValueText == "Working")
    }

    @Test("symbol name is bubble.left.fill")
    func symbolNameIsBubble() {
        #expect(ClaudeDockButton.symbolName == "bubble.left.fill")
    }
}
