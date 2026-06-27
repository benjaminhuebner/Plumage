import Testing

@testable import Plumage

@Suite("TerminalWheelAccumulator")
struct TerminalWheelAccumulatorTests {
    @Test("precise deltas below one notch accumulate without emitting")
    func subNotchAccumulates() {
        var acc = TerminalWheelAccumulator()
        #expect(acc.notches(forPreciseDelta: 1) == 0)
        #expect(acc.notches(forPreciseDelta: 1) == 0)
        // Third point crosses pointsPerNotch (3) → one notch.
        #expect(acc.notches(forPreciseDelta: 1) == 1)
    }

    @Test("a large precise delta emits multiple notches at once")
    func multipleNotches() {
        var acc = TerminalWheelAccumulator()
        #expect(acc.notches(forPreciseDelta: 10) == 3)
        // Remainder (10 - 9 = 1) carries forward.
        #expect(acc.notches(forPreciseDelta: 2) == 1)
    }

    @Test("negative precise deltas emit negative notches")
    func negativeDirection() {
        var acc = TerminalWheelAccumulator()
        #expect(acc.notches(forPreciseDelta: -9) == -3)
    }

    @Test("the fractional remainder carries across events")
    func carryAcrossEvents() {
        var acc = TerminalWheelAccumulator()
        #expect(acc.notches(forPreciseDelta: 2) == 0)
        #expect(acc.notches(forPreciseDelta: 2) == 1)
        #expect(acc.carry == 1)
    }

    @Test("reset clears the carried remainder")
    func resetClearsCarry() {
        var acc = TerminalWheelAccumulator()
        _ = acc.notches(forPreciseDelta: 2)
        acc.reset()
        #expect(acc.carry == 0)
        #expect(acc.notches(forPreciseDelta: 1) == 0)
    }

    @Test("classic line deltas map one notch per line")
    func lineDeltaMapsPerLine() {
        var acc = TerminalWheelAccumulator()
        #expect(acc.notches(forLineDelta: 3) == 3)
        #expect(acc.notches(forLineDelta: -1) == -1)
    }

    @Test("button direction follows SwiftTerm's wheel convention")
    func buttonDirection() {
        #expect(TerminalWheelAccumulator.button(forNotchDirection: 2) == 4)
        #expect(TerminalWheelAccumulator.button(forNotchDirection: -2) == 5)
        #expect(TerminalWheelAccumulator.button(forNotchDirection: 0) == nil)
    }
}
