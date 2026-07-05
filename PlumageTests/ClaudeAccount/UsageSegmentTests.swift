import Testing

@testable import Plumage

@Suite("Usage pill segment selection")
struct UsageSegmentTests {
    @Test("no window selected yields no segments")
    func noneSelected() {
        let response = makeResponse(fiveHour: 42, sevenDay: 18)
        #expect(response.pillSegments(showFiveHour: false, showSevenDay: false).isEmpty)
    }

    @Test("5-hour only yields one segment")
    func fiveHourOnly() {
        let response = makeResponse(fiveHour: 42, sevenDay: 18)
        let segments = response.pillSegments(showFiveHour: true, showSevenDay: false)
        #expect(segments == [UsageSegment(label: "5h", pct: 42)])
    }

    @Test("7-day only yields one segment")
    func sevenDayOnly() {
        let response = makeResponse(fiveHour: 42, sevenDay: 18)
        let segments = response.pillSegments(showFiveHour: false, showSevenDay: true)
        #expect(segments == [UsageSegment(label: "7d", pct: 18)])
    }

    @Test("both selected keeps 5h before 7d")
    func bothSelected() {
        let response = makeResponse(fiveHour: 42, sevenDay: 18)
        let segments = response.pillSegments(showFiveHour: true, showSevenDay: true)
        #expect(segments.map(\.label) == ["5h", "7d"])
        #expect(segments.map(\.pct) == [42, 18])
    }

    @Test("selected windows with no data yield no segments")
    func emptyData() {
        let response = makeResponse(fiveHour: nil, sevenDay: nil)
        #expect(response.pillSegments(showFiveHour: true, showSevenDay: true).isEmpty)
    }

    @Test("a checked window that is absent is omitted, not shown")
    func absentWindowOmitted() {
        let response = makeResponse(fiveHour: 42, sevenDay: nil)
        let segments = response.pillSegments(showFiveHour: true, showSevenDay: true)
        #expect(segments.map(\.label) == ["5h"])
    }

    private func makeResponse(fiveHour: Double? = nil, sevenDay: Double? = nil) -> ClaudeUsageResponse {
        func window(_ value: Double?) -> ClaudeUsageResponse.WindowUsage? {
            value.map { ClaudeUsageResponse.WindowUsage(utilizationPct: $0, resetsAt: nil) }
        }
        return ClaudeUsageResponse(fiveHour: window(fiveHour), sevenDay: window(sevenDay))
    }
}
