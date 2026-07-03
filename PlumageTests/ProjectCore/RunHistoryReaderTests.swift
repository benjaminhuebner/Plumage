import Foundation
import Testing

@testable import Plumage

struct RunHistoryReaderTests {
    private func makeProject() throws -> (root: URL, historyBase: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunHistoryReaderTests-\(UUID().uuidString)", isDirectory: true)
        let historyBase = root.appendingPathComponent(
            "Test.plumage/runs/history", isDirectory: true)
        try FileManager.default.createDirectory(at: historyBase, withIntermediateDirectories: true)
        return (root, historyBase)
    }

    private func writeRecord(
        slug: String, stamp: String, finishedAt: String, outcome: String, in historyBase: URL
    ) throws {
        let dir = historyBase.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        {"kind": "implement", "issue": "\(slug)",
         "finishedAt": "\(finishedAt)", "outcome": "\(outcome)",
         "lastCompletedTask": 2, "totalTasks": 5}
        """.write(
            to: dir.appendingPathComponent("\(stamp).json"), atomically: true, encoding: .utf8)
    }

    @Test("records come back newest first with outcome and finishedAt decoded")
    func newestFirst() throws {
        let (root, historyBase) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRecord(
            slug: "00042-a", stamp: "20260701T100000Z", finishedAt: "2026-07-01T10:00:00Z",
            outcome: "crashed", in: historyBase)
        try writeRecord(
            slug: "00042-a", stamp: "20260702T100000Z", finishedAt: "2026-07-02T10:00:00Z",
            outcome: "completed", in: historyBase)

        let page = RunHistoryReader.page(forSlug: "00042-a", acrossRoots: [root])

        #expect(page.totalCount == 2)
        #expect(page.records.map(\.outcome) == ["completed", "crashed"])
        #expect(page.records.first?.finishedAt == ISO8601Flexible.date(from: "2026-07-02T10:00:00Z"))
        #expect(page.records.first?.state.lastCompletedTask == 2)
    }

    @Test("limit caps the records but the total keeps counting")
    func limitAndTotal() throws {
        let (root, historyBase) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        for day in 1...5 {
            try writeRecord(
                slug: "00042-a", stamp: "2026070\(day)T100000Z",
                finishedAt: "2026-07-0\(day)T10:00:00Z", outcome: "completed", in: historyBase)
        }

        let page = RunHistoryReader.page(forSlug: "00042-a", acrossRoots: [root], limit: 3)

        #expect(page.records.count == 3)
        #expect(page.totalCount == 5)
        #expect(page.records.first?.finishedAt == ISO8601Flexible.date(from: "2026-07-05T10:00:00Z"))
    }

    @Test("malformed records are skipped, other slugs invisible")
    func malformedSkipped() throws {
        let (root, historyBase) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRecord(
            slug: "00042-a", stamp: "20260701T100000Z", finishedAt: "2026-07-01T10:00:00Z",
            outcome: "completed", in: historyBase)
        try writeRecord(
            slug: "00043-b", stamp: "20260701T100000Z", finishedAt: "2026-07-01T10:00:00Z",
            outcome: "crashed", in: historyBase)
        let dir = historyBase.appendingPathComponent("00042-a", isDirectory: true)
        try #"{"broken"#.write(
            to: dir.appendingPathComponent("20260702T100000Z.json"),
            atomically: true, encoding: .utf8)

        let page = RunHistoryReader.page(forSlug: "00042-a", acrossRoots: [root])

        #expect(page.totalCount == 1)
        #expect(page.records.map(\.outcome) == ["completed"])
    }

    @Test("records merge across worktree roots")
    func mergesAcrossRoots() throws {
        let (primary, primaryHistory) = try makeProject()
        let (worktree, worktreeHistory) = try makeProject()
        defer {
            try? FileManager.default.removeItem(at: primary)
            try? FileManager.default.removeItem(at: worktree)
        }
        try writeRecord(
            slug: "00042-a", stamp: "20260701T100000Z", finishedAt: "2026-07-01T10:00:00Z",
            outcome: "crashed", in: primaryHistory)
        try writeRecord(
            slug: "00042-a", stamp: "20260702T100000Z", finishedAt: "2026-07-02T10:00:00Z",
            outcome: "completed", in: worktreeHistory)

        let page = RunHistoryReader.page(forSlug: "00042-a", acrossRoots: [primary, worktree])

        #expect(page.totalCount == 2)
        #expect(page.records.map(\.outcome) == ["completed", "crashed"])
    }

    @Test(
        "outcome kinds classify for badge coloring",
        arguments: [
            ("completed", RunHistoryRecord.OutcomeKind.completed),
            ("failed at task 5", .failed),
            ("crashed", .crashed),
            ("something new", .crashed),
        ] as [(String, RunHistoryRecord.OutcomeKind)]
    )
    func outcomeKinds(outcome: String, expected: RunHistoryRecord.OutcomeKind) {
        let record = RunHistoryRecord(
            state: RunState(
                kind: "implement", runId: nil, issue: nil, startedAt: nil, agentPid: nil,
                phase: nil, lastProgressAt: nil, branch: nil, lastCompletedTask: nil,
                totalTasks: nil
            ),
            finishedAt: nil,
            outcome: outcome
        )
        #expect(record.outcomeKind == expected)
    }
}
