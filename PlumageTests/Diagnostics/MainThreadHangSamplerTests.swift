import Testing

@testable import Plumage

@Suite("HangStats aggregation")
struct HangStatsTests {
    @Test("tracks max stall, over-threshold count, and sample count")
    func aggregates() {
        var stats = HangStats()

        var isNewMax = stats.record(stallMs: 50, thresholdMs: 100)
        #expect(isNewMax)
        #expect(stats.maxStallMs == 50)
        #expect(stats.stallCount == 0)
        #expect(stats.sampleCount == 1)

        isNewMax = stats.record(stallMs: 150, thresholdMs: 100)
        #expect(isNewMax)
        #expect(stats.maxStallMs == 150)
        #expect(stats.stallCount == 1)

        isNewMax = stats.record(stallMs: 120, thresholdMs: 100)
        #expect(!isNewMax)
        #expect(stats.maxStallMs == 150)
        #expect(stats.stallCount == 2)
        #expect(stats.sampleCount == 3)
    }
}
