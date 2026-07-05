import Testing

@testable import Plumage

struct FrameSyncThrottleTests {
    @Test func firstDecisionAppliesImmediately() {
        var throttle = FrameSyncThrottle()
        #expect(throttle.decide(now: .now) == .applyNow)
    }

    @Test func defaultGapStaysDragResponsive() {
        // 50 ms keeps the pane edge tracking a sash drag; a larger gap reads
        // as the terminal lagging behind the divider.
        #expect(FrameSyncThrottle().minimumGap == .milliseconds(50))
    }

    @Test func burstWithinGapDefers() {
        var throttle = FrameSyncThrottle(minimumGap: .milliseconds(90))
        let start = ContinuousClock.now
        #expect(throttle.decide(now: start) == .applyNow)
        #expect(throttle.decide(now: start + .milliseconds(10)) == .deferTrailing)
        #expect(throttle.decide(now: start + .milliseconds(89)) == .deferTrailing)
    }

    @Test func applyResumesAfterGap() {
        var throttle = FrameSyncThrottle(minimumGap: .milliseconds(90))
        let start = ContinuousClock.now
        #expect(throttle.decide(now: start) == .applyNow)
        #expect(throttle.decide(now: start + .milliseconds(95)) == .applyNow)
        // The second apply resets the window.
        #expect(throttle.decide(now: start + .milliseconds(100)) == .deferTrailing)
        #expect(throttle.decide(now: start + .milliseconds(200)) == .applyNow)
    }

    @Test func deferralsDoNotResetTheGapWindow() {
        var throttle = FrameSyncThrottle(minimumGap: .milliseconds(90))
        let start = ContinuousClock.now
        #expect(throttle.decide(now: start) == .applyNow)
        for offset in stride(from: 10, through: 80, by: 10) {
            #expect(throttle.decide(now: start + .milliseconds(offset)) == .deferTrailing)
        }
        #expect(throttle.decide(now: start + .milliseconds(91)) == .applyNow)
    }
}
