import Foundation
import Testing

@testable import Plumage

struct CrashedRunSweeperTests {
    private func makeProject() throws -> (root: URL, runsDir: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashedRunSweeperTests-\(UUID().uuidString)", isDirectory: true)
        let runsDir = root.appendingPathComponent("Test.plumage/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        return (root, runsDir)
    }

    private func makeSnapshot(
        root: URL,
        slug: String = "00042-some-issue",
        phase: String? = "running task 2",
        agentPid: Int? = 0,
        isAgentAlive: Bool = false,
        lastProgressAt: Date? = .distantPast
    ) -> RunStateSnapshot {
        RunStateSnapshot(
            checkoutRoot: root,
            slug: slug,
            state: RunState(
                kind: "implement", runId: nil, issue: slug, startedAt: lastProgressAt,
                agentPid: agentPid, phase: phase, lastProgressAt: lastProgressAt,
                branch: nil, lastCompletedTask: 1, totalTasks: 3
            ),
            isAgentAlive: isAgentAlive
        )
    }

    private func writeRunState(
        slug: String, phase: String, agentPid: Int, lastProgressAt: Date, in runsDir: URL,
        extraField: Bool = false
    ) throws {
        let extra = extraField ? #""plumagePid": 12345,"# : ""
        try """
        {"kind": "implement", "issue": "\(slug)", \(extra)
         "agentPid": \(agentPid), "phase": "\(phase)",
         "lastProgressAt": "\(ISO8601Flexible.string(from: lastProgressAt))",
         "lastCompletedTask": 1, "totalTasks": 3}
        """.write(
            to: runsDir.appendingPathComponent("\(slug).json"),
            atomically: true, encoding: .utf8)
    }

    // MARK: outcome

    @Test("failed phase carries through as the outcome")
    func failedOutcome() {
        let state = makeSnapshot(root: URL(filePath: "/tmp"), phase: "failed at task 5").state
        #expect(CrashedRunSweeper.outcome(for: state) == "failed at task 5")
    }

    @Test("non-failed phases classify as crashed", arguments: ["running task 2", "starting", nil])
    func crashedOutcome(phase: String?) {
        let state = makeSnapshot(root: URL(filePath: "/tmp"), phase: phase).state
        #expect(CrashedRunSweeper.outcome(for: state) == "crashed")
    }

    // MARK: eligibility

    @Test("live pid is never eligible, no matter how stale")
    func liveNeverEligible() {
        let snapshot = makeSnapshot(
            root: URL(filePath: "/tmp"), isAgentAlive: true, lastProgressAt: .distantPast)
        #expect(!CrashedRunSweeper.isEligible(snapshot, queuedSlugs: [], now: .now))
    }

    @Test("dead pid within the grace period is not eligible")
    func deadRecentNotEligible() {
        let snapshot = makeSnapshot(
            root: URL(filePath: "/tmp"), lastProgressAt: Date.now.addingTimeInterval(-10))
        #expect(!CrashedRunSweeper.isEligible(snapshot, queuedSlugs: [], now: .now, grace: 120))
    }

    @Test("dead pid past the grace period is eligible")
    func deadStaleEligible() {
        let snapshot = makeSnapshot(
            root: URL(filePath: "/tmp"), lastProgressAt: Date.now.addingTimeInterval(-300))
        #expect(CrashedRunSweeper.isEligible(snapshot, queuedSlugs: [], now: .now, grace: 120))
    }

    @Test("a queued slug is never eligible")
    func queuedNotEligible() {
        let snapshot = makeSnapshot(root: URL(filePath: "/tmp"), lastProgressAt: .distantPast)
        #expect(
            !CrashedRunSweeper.isEligible(
                snapshot, queuedSlugs: ["00042-some-issue"], now: .now))
    }

    @Test("missing timestamps make a dead run eligible immediately")
    func noTimestampsEligible() {
        let snapshot = makeSnapshot(root: URL(filePath: "/tmp"), lastProgressAt: nil)
        #expect(CrashedRunSweeper.isEligible(snapshot, queuedSlugs: [], now: .now))
    }

    // MARK: sweep on disk

    @Test("eligible run moves to history enriched with outcome and finishedAt")
    func sweepMovesToHistory() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRunState(
            slug: "00042-some-issue", phase: "running task 2", agentPid: 0,
            lastProgressAt: .distantPast, in: runsDir, extraField: true)
        let snapshot = makeSnapshot(root: root)

        let swept = CrashedRunSweeper.sweep(snapshots: [snapshot], queuedSlugs: { _ in [] })

        #expect(swept == 1)
        #expect(!FileManager.default.fileExists(atPath: runsDir.appendingPathComponent("00042-some-issue.json").path))
        let historyDir = runsDir.appendingPathComponent("history/00042-some-issue")
        let entries = try FileManager.default.contentsOfDirectory(
            at: historyDir, includingPropertiesForKeys: nil)
        let record = try #require(entries.first)
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
        #expect(json["outcome"] as? String == "crashed")
        #expect(json["finishedAt"] as? String != nil)
        #expect(json["plumagePid"] as? Int == 12345)
    }

    @Test("failed run keeps its failure as the history outcome")
    func sweepKeepsFailedOutcome() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRunState(
            slug: "00042-some-issue", phase: "failed at task 2", agentPid: 0,
            lastProgressAt: .distantPast, in: runsDir)
        let snapshot = makeSnapshot(root: root, phase: "failed at task 2")

        let swept = CrashedRunSweeper.sweep(snapshots: [snapshot], queuedSlugs: { _ in [] })

        #expect(swept == 1)
        let historyDir = runsDir.appendingPathComponent("history/00042-some-issue")
        let record = try #require(
            try FileManager.default.contentsOfDirectory(
                at: historyDir, includingPropertiesForKeys: nil
            ).first)
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
        #expect(json["outcome"] as? String == "failed at task 2")
    }

    @Test("a rewritten run-state with a live pid is skipped on the fresh read")
    func rewrittenLiveRunSkipped() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        // The stale snapshot says dead, but the file now carries a live pid —
        // a resume rewrote it between scan and sweep.
        try writeRunState(
            slug: "00042-some-issue", phase: "running task 2",
            agentPid: Int(ProcessInfo.processInfo.processIdentifier),
            lastProgressAt: .distantPast, in: runsDir)
        let snapshot = makeSnapshot(root: root)

        let swept = CrashedRunSweeper.sweep(snapshots: [snapshot], queuedSlugs: { _ in [] })

        #expect(swept == 0)
        #expect(FileManager.default.fileExists(atPath: runsDir.appendingPathComponent("00042-some-issue.json").path))
        #expect(
            !FileManager.default.fileExists(atPath: runsDir.appendingPathComponent("history/00042-some-issue").path))
    }

    @Test("a concurrent rewrite between read and remove rolls the history copy back")
    func resumeRaceRollsBack() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRunState(
            slug: "00042-some-issue", phase: "running task 2", agentPid: 0,
            lastProgressAt: .distantPast, in: runsDir)
        let snapshot = makeSnapshot(root: root)
        let raceOps = RaceForcingFileOps()

        let swept = CrashedRunSweeper.sweep(
            snapshots: [snapshot], fileOps: raceOps, queuedSlugs: { _ in [] })

        #expect(swept == 0)
        #expect(FileManager.default.fileExists(atPath: runsDir.appendingPathComponent("00042-some-issue.json").path))
        let historyDir = runsDir.appendingPathComponent("history/00042-some-issue")
        let leftovers =
            (try? FileManager.default.contentsOfDirectory(
                at: historyDir, includingPropertiesForKeys: nil)) ?? []
        #expect(leftovers.isEmpty)
    }
}

// Forces the resume race: identity always mismatches at remove time, as if the
// run-state was rewritten between the sweep's read and its remove.
private struct RaceForcingFileOps: RunSweepFileOps {
    private let production = ProductionRunSweepFileOps()

    func read(at url: URL) throws -> Data { try production.read(at: url) }
    func identity(at url: URL) throws -> RunFileIdentity { try production.identity(at: url) }
    func createDirectory(at url: URL) throws { try production.createDirectory(at: url) }
    func writeAtomic(_ data: Data, to url: URL) throws {
        try production.writeAtomic(data, to: url)
    }
    func removeIfUnchanged(at url: URL, identity: RunFileIdentity) throws -> Bool { false }
    func remove(at url: URL) throws { try production.remove(at: url) }
}
