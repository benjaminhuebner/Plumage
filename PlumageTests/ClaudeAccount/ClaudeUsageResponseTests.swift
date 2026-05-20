import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeUsageResponse decoder")
struct ClaudeUsageResponseTests {
    @Test("decodes Pro-account fixture")
    func decodesPro() throws {
        let data = try fixture(named: "usage-response-pro")
        let response = try ClaudeUsageResponse.decode(data: data)
        #expect(response.fiveHour?.utilizationPct == 42.5)
        #expect(response.sevenDay?.utilizationPct == 13.0)
        #expect(response.sevenDayOpus == nil)
        #expect(response.sevenDaySonnet == nil)
        let resets = try #require(response.fiveHour?.resetsAt)
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(expected.date(from: "2026-05-20T22:00:00.000Z") == resets)
    }

    @Test("decodes Max-account fixture with Opus + Sonnet")
    func decodesMax() throws {
        let data = try fixture(named: "usage-response-max")
        let response = try ClaudeUsageResponse.decode(data: data)
        #expect(response.fiveHour?.utilizationPct == 87.25)
        #expect(response.sevenDay?.utilizationPct == 64.0)
        #expect(response.sevenDayOpus?.utilizationPct == 18.5)
        #expect(response.sevenDaySonnet?.utilizationPct == 4.0)
    }

    @Test("tolerates missing windows")
    func decodesEmpty() throws {
        let data = Data("{}".utf8)
        let response = try ClaudeUsageResponse.decode(data: data)
        #expect(response.fiveHour == nil)
        #expect(response.sevenDay == nil)
        #expect(response.sevenDayOpus == nil)
        #expect(response.sevenDaySonnet == nil)
    }

    @Test("drops window when utilization is missing")
    func dropsWindowWithoutUtilization() throws {
        let json = #"""
            {
              "five_hour": { "resets_at": "2026-05-20T22:00:00Z" }
            }
            """#
        let response = try ClaudeUsageResponse.decode(data: Data(json.utf8))
        #expect(response.fiveHour == nil)
    }

    @Test("accepts Unix-seconds timestamps")
    func acceptsUnixSeconds() throws {
        let json = #"""
            {
              "five_hour": { "utilization": 10, "resets_at": 1747862400 }
            }
            """#
        let response = try ClaudeUsageResponse.decode(data: Data(json.utf8))
        let resets = try #require(response.fiveHour?.resetsAt)
        #expect(resets.timeIntervalSince1970 == 1_747_862_400)
    }

    private func fixture(named name: String) throws -> Data {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: "\(name).json")
        return try Data(contentsOf: url)
    }
}
