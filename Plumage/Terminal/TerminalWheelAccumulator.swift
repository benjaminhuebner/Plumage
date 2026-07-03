// Sub-notch trackpad deltas accumulate in `carry`; whole notches emit and the
// remainder carries to the next event so slow drags still scroll.
nonisolated struct TerminalWheelAccumulator {
    private(set) var carry: Double = 0
    static let pointsPerNotch: Double = 3

    mutating func notches(forPreciseDelta delta: Double) -> Int {
        carry += delta
        let whole = (carry / Self.pointsPerNotch).rounded(.towardZero)
        carry -= whole * Self.pointsPerNotch
        return Int(whole)
    }

    // Classic wheels report deltaY already in lines — one notch per line.
    mutating func notches(forLineDelta delta: Double) -> Int {
        carry += delta
        let whole = carry.rounded(.towardZero)
        carry -= whole
        return Int(whole)
    }

    mutating func reset() { carry = 0 }

    // SwiftTerm wheel convention: positive delta scrolls toward history
    // (wheel-up, button 4 → Cb 64), negative toward newer output (button 5 → 65).
    static func button(forNotchDirection direction: Int) -> Int? {
        if direction > 0 { return 4 }
        if direction < 0 { return 5 }
        return nil
    }
}
