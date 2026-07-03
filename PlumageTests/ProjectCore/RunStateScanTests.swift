import Foundation
import Testing

@testable import Plumage

struct RunStateScanTests {
    private func makeProject() throws -> (root: URL, runsDir: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunStateScanTests-\(UUID().uuidString)", isDirectory: true)
        let runsDir = root.appendingPathComponent("Test.plumage/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        return (root, runsDir)
    }

    private func write(_ json: String, slug: String, in runsDir: URL) throws {
        try json.write(
            to: runsDir.appendingPathComponent("\(slug).json"), atomically: true, encoding: .utf8)
    }

    private static func deadPid() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    @Test("live run surfaces with full decoded state")
    func liveRunDecoded() throws {
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

        let snapshots = ImplementRunScanner.runStates(in: root)
        let snapshot = try #require(snapshots.first)
        #expect(snapshots.count == 1)
        #expect(snapshot.slug == "00042-some-issue")
        #expect(snapshot.isAgentAlive)
        #expect(snapshot.state.phase == "running task 3")
        #expect(snapshot.state.lastCompletedTask == 2)
        #expect(snapshot.state.totalTasks == 7)
        #expect(snapshot.checkoutRoot == root)
    }

    @Test("dead run is included but marked not alive")
    func deadRunIncluded() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            #"{"kind": "implement", "issue": "00013-dead", "agentPid": \#(Self.deadPid())}"#,
            slug: "00013-dead", in: runsDir
        )

        let snapshots = ImplementRunScanner.runStates(in: root)
        let snapshot = try #require(snapshots.first)
        #expect(!snapshot.isAgentAlive)
        #expect(snapshot.slug == "00013-dead")
    }

    @Test("malformed run-state and non-implement kinds are skipped")
    func malformedAndForeignSkipped() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(#"{"kind": "implement", "totalTa"#, slug: "00001-broken", in: runsDir)
        try write(#"{"kind": "plan-issue", "agentPid": 1}"#, slug: "00002-plan", in: runsDir)
        try write(#"{"kind": "implement", "issue": "00003-ok"}"#, slug: "00003-ok", in: runsDir)

        let snapshots = ImplementRunScanner.runStates(in: root)
        #expect(snapshots.map(\.slug) == ["00003-ok"])
        #expect(snapshots.first?.isAgentAlive == false)
    }

    @Test("missing agentPid means not alive")
    func missingPidNotAlive() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(#"{"kind": "implement", "issue": "00005-no-pid"}"#, slug: "00005-no-pid", in: runsDir)

        let snapshot = try #require(ImplementRunScanner.runStates(in: root).first)
        #expect(!snapshot.isAgentAlive)
    }

    @Test("slug falls back to the file name")
    func slugFallsBackToFileName() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(#"{"kind": "implement"}"#, slug: "00007-nameless", in: runsDir)

        let snapshot = try #require(ImplementRunScanner.runStates(in: root).first)
        #expect(snapshot.slug == "00007-nameless")
    }

    @Test("scan across worktree roots tags each snapshot with its checkout root")
    func worktreeScan() throws {
        let (primary, primaryRuns) = try makeProject()
        let (worktree, worktreeRuns) = try makeProject()
        defer {
            try? FileManager.default.removeItem(at: primary)
            try? FileManager.default.removeItem(at: worktree)
        }
        try write(#"{"kind": "implement", "issue": "00010-a"}"#, slug: "00010-a", in: primaryRuns)
        try write(#"{"kind": "implement", "issue": "00011-b"}"#, slug: "00011-b", in: worktreeRuns)

        let snapshots = ImplementRunScanner.runStates(acrossWorktreeRoots: [primary, worktree])
        #expect(snapshots.count == 2)
        #expect(snapshots.first { $0.slug == "00010-a" }?.checkoutRoot == primary)
        #expect(snapshots.first { $0.slug == "00011-b" }?.checkoutRoot == worktree)
    }
}
