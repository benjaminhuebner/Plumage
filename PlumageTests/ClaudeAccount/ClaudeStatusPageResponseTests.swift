import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeStatusPageResponse decoder")
struct ClaudeStatusPageResponseTests {
    @Test("decodes operational summary")
    func decodesOperational() throws {
        let data = try fixture(named: "status-operational")
        let response = try ClaudeStatusPageResponse.decode(data: data)
        #expect(response.indicator == .none)
        #expect(response.description == "All Systems Operational")
        #expect(response.component?.name == "Claude Code")
        #expect(response.component?.status == "operational")
        #expect(response.incidents.isEmpty)
        let updatedAt = try #require(response.updatedAt)
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(expected.date(from: "2026-05-20T18:00:00.000Z") == updatedAt)
    }

    @Test("decodes major incident summary")
    func decodesIncident() throws {
        let data = try fixture(named: "status-incident")
        let response = try ClaudeStatusPageResponse.decode(data: data)
        #expect(response.indicator == .major)
        #expect(response.description == "Elevated API errors")
        #expect(response.component?.status == "degraded_performance")
        #expect(response.incidents.count == 2)
        let first = try #require(response.incidents.first)
        #expect(first.name == "Increased latency on Sonnet")
        #expect(first.impact == "major")
    }

    @Test("maps unknown indicator to .unknown")
    func mapsUnknown() {
        #expect(ClaudeStatusIndicator.parse("space-weather") == .unknown)
        #expect(ClaudeStatusIndicator.parse(nil) == .unknown)
        #expect(ClaudeStatusIndicator.parse("MAJOR") == .major)
        #expect(ClaudeStatusIndicator.parse("maintenance") == .maintenance)
    }

    @Test("falls back when status block is missing")
    func defaultsOnMissingStatus() throws {
        let data = Data(#"{ "page": { "updated_at": "2026-05-20T19:00:00Z" } }"#.utf8)
        let response = try ClaudeStatusPageResponse.decode(data: data)
        #expect(response.indicator == .unknown)
        #expect(response.description == "Unknown status")
        #expect(response.component == nil)
        #expect(response.incidents.isEmpty)
    }

    private func fixture(named name: String) throws -> Data {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: "\(name).json")
        return try Data(contentsOf: url)
    }
}
