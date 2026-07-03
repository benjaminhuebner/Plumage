import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("RunStatusModel")
struct RunStatusModelTests {
    private func makeProject() throws -> (root: URL, runsDir: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunStatusModelTests-\(UUID().uuidString)", isDirectory: true)
        let runsDir = root.appendingPathComponent("Test.plumage/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        return (root, runsDir)
    }

    private func write(_ json: String, slug: String, in runsDir: URL) throws {
        try json.write(
            to: runsDir.appendingPathComponent("\(slug).json"), atomically: true, encoding: .utf8)
    }

    private func makeNotifier() -> RunCompletionNotifier {
        RunCompletionNotifier(isFrontmost: { true }, post: { _, _, _, _, _ in })
    }

    @Test("refresh publishes live runs with decoded phase and progress")
    func refreshPublishesLiveRuns() async throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let livePid = ProcessInfo.processInfo.processIdentifier
        try write(
            """
            {"kind": "implement", "issue": "00042-some-issue", "agentPid": \(livePid),
             "phase": "running task 3", "lastCompletedTask": 2, "totalTasks": 7}
            """,
            slug: "00042-some-issue", in: runsDir
        )

        let model = RunStatusModel()
        model.start(projectURL: root, notifier: makeNotifier())
        await model.refresh()

        let run = try #require(model.liveRuns["00042-some-issue"])
        #expect(run.state.phase == "running task 3")
        #expect(run.state.totalTasks == 7)
        #expect(!run.isWorktree)
        model.stop()
    }

    @Test("dead run within the sweep grace period stays in snapshots, not in liveRuns")
    func deadRunNotLive() async throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let recent = ISO8601Flexible.string(from: .now)
        try write(
            #"{"kind": "implement", "issue": "00013-dead", "agentPid": 0, "lastProgressAt": "\#(recent)"}"#,
            slug: "00013-dead", in: runsDir
        )

        let model = RunStatusModel()
        model.start(projectURL: root, notifier: makeNotifier())
        await model.refresh()

        #expect(model.liveRuns.isEmpty)
        #expect(model.runSnapshots.map(\.slug) == ["00013-dead"])
        model.stop()
    }

    @Test("queued runs surface in FIFO order")
    func queuedRunsFIFO() async throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let queueDir = runsDir.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        let livePid = ProcessInfo.processInfo.processIdentifier
        for (seq, slug) in [("000002", "00021-second"), ("000001", "00020-first")] {
            try #"{"slug": "\#(slug)", "agentPid": \#(livePid)}"#.write(
                to: queueDir.appendingPathComponent("\(seq)-\(slug).json"),
                atomically: true, encoding: .utf8)
        }

        let model = RunStatusModel()
        model.start(projectURL: root, notifier: makeNotifier())
        await model.refresh()

        #expect(model.queuedRuns.map(\.issue) == ["00020-first", "00021-second"])
        model.stop()
    }

    @Test("worktree run is keyed by slug and marked as worktree")
    func worktreeRunMarked() async throws {
        let (primary, _) = try makeProject()
        let (worktree, worktreeRuns) = try makeProject()
        defer {
            try? FileManager.default.removeItem(at: primary)
            try? FileManager.default.removeItem(at: worktree)
        }
        let livePid = ProcessInfo.processInfo.processIdentifier
        try write(
            #"{"kind": "implement", "issue": "00011-b", "agentPid": \#(livePid)}"#,
            slug: "00011-b", in: worktreeRuns
        )

        let model = RunStatusModel(rootsProvider: { _ in [primary, worktree] })
        model.start(projectURL: primary, notifier: makeNotifier())
        await model.refresh()

        let run = try #require(model.liveRuns["00011-b"])
        #expect(run.isWorktree)
        #expect(run.checkoutRoot == worktree)
        model.stop()
    }

    @Test("notifier event triggers a refresh")
    func notifierEventRefreshes() async throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let notifier = makeNotifier()
        let model = RunStatusModel()
        model.start(projectURL: root, notifier: notifier)
        await model.refresh()

        let livePid = ProcessInfo.processInfo.processIdentifier
        try write(
            #"{"kind": "implement", "issue": "00042-some-issue", "agentPid": \#(livePid)}"#,
            slug: "00042-some-issue", in: runsDir
        )
        notifier.checkFinished(root: root)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.liveRuns["00042-some-issue"] == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(model.liveRuns["00042-some-issue"] != nil)
        model.stop()
    }

    @Test("resume is available only for in-progress issues with no live or queued run")
    func resumeAvailability() {
        #expect(
            RunStatusModel.resumeAvailable(status: .inProgress, hasLiveRun: false, isQueued: false))
        #expect(
            !RunStatusModel.resumeAvailable(status: .inProgress, hasLiveRun: true, isQueued: false))
        #expect(
            !RunStatusModel.resumeAvailable(status: .inProgress, hasLiveRun: false, isQueued: true))
        #expect(
            !RunStatusModel.resumeAvailable(status: .approved, hasLiveRun: false, isQueued: false))
        #expect(
            !RunStatusModel.resumeAvailable(
                status: .waitingForReview, hasLiveRun: false, isQueued: false))
    }

    @Test("stop deregisters: later events no longer refresh")
    func stopDeregisters() async throws {
        let (root, _) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let notifier = makeNotifier()
        let model = RunStatusModel()
        model.start(projectURL: root, notifier: notifier)
        await model.refresh()
        model.stop()
        let before = model.revision

        notifier.checkFinished(root: root)
        await Task.yield()
        await Task.yield()

        #expect(model.revision == before)
    }
}
