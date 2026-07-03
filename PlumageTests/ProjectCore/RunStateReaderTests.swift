import Foundation
import Testing

@testable import Plumage

struct RunStateReaderTests {
    private func decode(_ json: String) throws -> RunState {
        try RunStateReader.decode(Data(json.utf8))
    }

    @Test("full run-state decodes every field")
    func fullDecode() throws {
        let state = try decode(
            """
            {
              "kind": "implement",
              "runId": "01HXY7ZA8K9P3QRSTV4WMNCDFG",
              "issue": "00042-add-user-auth",
              "startedAt": "2026-05-09T10:30:00Z",
              "agentPid": 47291,
              "phase": "running task 3",
              "lastProgressAt": "2026-05-09T10:38:01Z",
              "branch": "issue/00042-add-user-auth",
              "headBeforeRun": "abc123def456",
              "lastCompletedTask": 2,
              "totalTasks": 7
            }
            """)

        #expect(state.kind == "implement")
        #expect(state.runId == "01HXY7ZA8K9P3QRSTV4WMNCDFG")
        #expect(state.issue == "00042-add-user-auth")
        #expect(state.startedAt == ISO8601Flexible.date(from: "2026-05-09T10:30:00Z"))
        #expect(state.agentPid == 47291)
        #expect(state.phase == "running task 3")
        #expect(state.lastProgressAt == ISO8601Flexible.date(from: "2026-05-09T10:38:01Z"))
        #expect(state.branch == "issue/00042-add-user-auth")
        #expect(state.lastCompletedTask == 2)
        #expect(state.totalTasks == 7)
    }

    @Test("partial run-state decodes with nil optionals")
    func partialDecode() throws {
        let state = try decode(#"{"kind": "implement"}"#)

        #expect(state.kind == "implement")
        #expect(state.issue == nil)
        #expect(state.phase == nil)
        #expect(state.lastCompletedTask == nil)
        #expect(state.totalTasks == nil)
        #expect(state.lastProgressAt == nil)
        #expect(state.branch == nil)
    }

    @Test("zero totalTasks decodes as zero, not as an error")
    func zeroTotals() throws {
        let state = try decode(
            #"{"kind": "implement", "lastCompletedTask": 0, "totalTasks": 0}"#)

        #expect(state.lastCompletedTask == 0)
        #expect(state.totalTasks == 0)
    }

    @Test("plumage-owned fields are tolerated and ignored")
    func foreignFieldsIgnored() throws {
        let state = try decode(
            """
            {
              "kind": "implement",
              "plumagePid": 12345,
              "plumageHeartbeatAt": "2026-05-09T10:42:13Z",
              "agentLastOutputAt": "2026-05-09T10:42:08Z",
              "lastUserVisibleAction": "Approved spec edit"
            }
            """)

        #expect(state.kind == "implement")
    }

    @Test("fractional-second timestamps parse")
    func fractionalSeconds() throws {
        let state = try decode(
            #"{"kind": "implement", "lastProgressAt": "2026-05-09T10:38:01.123Z"}"#)

        #expect(state.lastProgressAt != nil)
    }

    @Test("truncated JSON is malformed")
    func truncatedJSON() {
        #expect(throws: RunStateReader.ReadError.malformed) {
            try self.decode(#"{"kind": "implement", "totalTa"#)
        }
    }

    @Test("missing kind is malformed")
    func missingKind() {
        #expect(throws: RunStateReader.ReadError.malformed) {
            try self.decode(#"{"issue": "00042-add-user-auth"}"#)
        }
    }

    @Test("non-numeric task counter is malformed")
    func nonNumericCounter() {
        #expect(throws: RunStateReader.ReadError.malformed) {
            try self.decode(#"{"kind": "implement", "totalTasks": "seven"}"#)
        }
    }

    @Test("unparseable timestamp is malformed")
    func unparseableTimestamp() {
        #expect(throws: RunStateReader.ReadError.malformed) {
            try self.decode(#"{"kind": "implement", "startedAt": "yesterday"}"#)
        }
    }

    @Test("JSON array is malformed")
    func arrayIsMalformed() {
        #expect(throws: RunStateReader.ReadError.malformed) {
            try self.decode(#"[{"kind": "implement"}]"#)
        }
    }

    @Test("missing file is unreadable")
    func missingFileUnreadable() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunStateReaderTests-\(UUID().uuidString).json")

        #expect(throws: RunStateReader.ReadError.unreadable) {
            try RunStateReader.read(at: url)
        }
    }

    @Test("read decodes a run-state file from disk")
    func readFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunStateReaderTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"kind": "implement", "issue": "00042-some-issue", "phase": "starting"}"#
            .write(to: url, atomically: true, encoding: .utf8)

        let state = try RunStateReader.read(at: url)
        #expect(state.issue == "00042-some-issue")
        #expect(state.phase == "starting")
    }
}
