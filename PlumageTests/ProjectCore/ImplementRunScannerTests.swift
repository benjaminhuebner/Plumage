import Foundation
import Testing

@testable import Plumage

struct ImplementRunScannerTests {
    private func makeProject() throws -> (root: URL, runsDir: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImplementRunScannerTests-\(UUID().uuidString)", isDirectory: true)
        let runsDir = root.appendingPathComponent("Test.plumage/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        return (root, runsDir)
    }

    private func writeRunState(
        _ json: String, slug: String = "00042-some-issue", in runsDir: URL
    ) throws {
        try json.write(
            to: runsDir.appendingPathComponent("\(slug).json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func deadPid() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    @Test("live implement run is found and named")
    func liveRunFound() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let livePid = ProcessInfo.processInfo.processIdentifier
        try writeRunState(
            #"{"kind": "implement", "issue": "00042-some-issue", "agentPid": \#(livePid)}"#,
            in: runsDir
        )

        let run = try #require(ImplementRunScanner.liveImplementRun(in: root))
        #expect(run.issue == "00042-some-issue")
        #expect(run.agentPid == livePid)
    }

    @Test("missing issue field falls back to the file name")
    func issueFallsBackToFileName() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let livePid = ProcessInfo.processInfo.processIdentifier
        try writeRunState(
            #"{"kind": "implement", "agentPid": \#(livePid)}"#,
            slug: "00007-nameless",
            in: runsDir
        )

        let run = try #require(ImplementRunScanner.liveImplementRun(in: root))
        #expect(run.issue == "00007-nameless")
    }

    @Test("dead agentPid is a crash leftover, not a blocker")
    func deadPidAllows() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let dead = try Self.deadPid()
        try writeRunState(
            #"{"kind": "implement", "issue": "00042-some-issue", "agentPid": \#(dead)}"#,
            in: runsDir
        )

        #expect(ImplementRunScanner.liveImplementRun(in: root) == nil)
    }

    @Test(
        "missing, zero, negative, and non-numeric agentPid are dead",
        arguments: [
            #"{"kind": "implement", "issue": "00042-some-issue"}"#,
            #"{"kind": "implement", "issue": "00042-some-issue", "agentPid": 0}"#,
            #"{"kind": "implement", "issue": "00042-some-issue", "agentPid": -1}"#,
            #"{"kind": "implement", "issue": "00042-some-issue", "agentPid": "47291"}"#,
        ]
    )
    func invalidPidAllows(json: String) throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRunState(json, in: runsDir)

        #expect(ImplementRunScanner.liveImplementRun(in: root) == nil)
    }

    @Test("malformed run-state is ignored")
    func malformedFileAllows() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRunState("{not json at all", in: runsDir)

        #expect(ImplementRunScanner.liveImplementRun(in: root) == nil)
    }

    @Test("non-implement kinds never block, even with a live PID")
    func foreignKindAllows() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let livePid = ProcessInfo.processInfo.processIdentifier
        try writeRunState(
            #"{"kind": "plan-issue", "issue": "00042-some-issue", "agentPid": \#(livePid)}"#,
            in: runsDir
        )

        #expect(ImplementRunScanner.liveImplementRun(in: root) == nil)
    }

    @Test("missing runs directory or bundle means no live run")
    func missingInfrastructureAllows() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: runsDir)
        #expect(ImplementRunScanner.liveImplementRun(in: root) == nil)

        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImplementRunScannerTests-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        #expect(ImplementRunScanner.liveImplementRun(in: emptyRoot) == nil)
    }

    @Test("dead leftover does not hide a later live run")
    func deadLeftoverPlusLiveRun() throws {
        let (root, runsDir) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let dead = try Self.deadPid()
        let livePid = ProcessInfo.processInfo.processIdentifier
        try writeRunState(
            #"{"kind": "implement", "issue": "00001-dead", "agentPid": \#(dead)}"#,
            slug: "00001-dead",
            in: runsDir
        )
        try writeRunState(
            #"{"kind": "implement", "issue": "00042-some-issue", "agentPid": \#(livePid)}"#,
            in: runsDir
        )

        let run = try #require(ImplementRunScanner.liveImplementRun(in: root))
        #expect(run.issue == "00042-some-issue")
    }
}
