import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TerminalClaudeSession", .serialized)
struct TerminalClaudeSessionTests {
    @Test("starts in .idle")
    func initialState() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        #expect(session.state == .idle)
    }

    @Test("attach() from .idle transitions to .starting(cwd:)")
    func attachTransitions() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        guard case .starting(let cwd) = session.state else {
            Issue.record("Expected .starting, got \(session.state)")
            return
        }
        #expect(cwd == session.cwd)
    }

    @Test("attach() from .running is a no-op")
    func attachIdempotent() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        let snapshot = session.state
        session.attach()
        #expect(session.state == snapshot)
    }

    @Test("attach() from .exited returns to .starting (restart path)")
    func attachAfterExitRestarts() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markExited(code: 1)
        session.attach()
        guard case .starting = session.state else {
            Issue.record("Expected .starting after restart, got \(session.state)")
            return
        }
    }

    @Test("markStarted only transitions when .starting")
    func markStartedGuards() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.markStarted()
        #expect(session.state == .idle)
        session.attach()
        session.markStarted()
        #expect(session.state == .running)
        session.markStarted()
        #expect(session.state == .running)
    }

    @Test("markExited classifies code 0 as userClosed")
    func exitZeroUserClosed() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        session.markExited(code: 0)
        #expect(session.state == .exited(code: 0, reason: .userClosed))
    }

    @Test("markExited classifies signal range 128..159 as killed")
    func exitKilledSignal() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        session.markExited(code: 143)
        #expect(session.state == .exited(code: 143, reason: .killed))
    }

    @Test("markExited classifies non-zero non-signal as crashed")
    func exitNonZeroCrashed() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        session.markExited(code: 2)
        #expect(session.state == .exited(code: 2, reason: .crashed))
    }

    @Test("stop() from .running transitions to .exited(userClosed)")
    func stopFromRunning() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        session.stop()
        #expect(session.state == .exited(code: 0, reason: .userClosed))
    }

    @Test("stop() from .idle is a no-op")
    func stopIdle() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.stop()
        #expect(session.state == .idle)
    }

    @Test("resumeOrInitArgs returns --session-id when claude log absent")
    func resumeArgsNewSession() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        let args = session.resumeOrInitArgs()
        #expect(args == ["--session-id", session.conversationID])
    }

    @Test("resumeOrInitArgs returns --resume when claude log exists")
    func resumeArgsExistingSession() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        try env.writeClaudeSessionLog(for: session.conversationID)
        let args = session.resumeOrInitArgs()
        #expect(args == ["--resume", session.conversationID])
    }

    @Test("shellSpawnArgs builds /bin/sh -c \"cd … && exec …\" form")
    func shellArgsForm() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        let args = session.shellSpawnArgs()
        #expect(args.count == 2)
        #expect(args[0] == "-c")
        #expect(args[1].hasPrefix("cd '"))
        #expect(args[1].contains("' && exec '"))
        #expect(args[1].contains(session.binaryURL.path))
        #expect(args[1].contains("--session-id"))
        #expect(args[1].contains(session.conversationID))
    }

    @Test("shellSpawnArgs single-quote-escapes ' inside cwd")
    func shellArgsEscapesQuotes() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let trickyCwd = env.cwdRoot.appendingPathComponent("o'tricky")
        try FileManager.default.createDirectory(at: trickyCwd, withIntermediateDirectories: true)
        let session = TerminalClaudeSession(
            cwd: trickyCwd,
            binaryURL: env.fakeBinary,
            sessionIDStoreOverride: env.sessionIDStore,
            sessionLogRoot: env.sessionLogRoot
        )
        let args = session.shellSpawnArgs()
        #expect(args[1].contains(#"o'\''tricky"#))
    }

    @Test("Conversation-ID is persisted and reused on second init")
    func uuidPersistence() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let first = env.makeSession()
        let firstID = first.conversationID
        // Independent second init reads the same store.
        let second = env.makeSession()
        #expect(second.conversationID == firstID)
    }

    @Test("Persisted ID survives across distinct cwds when store is shared")
    func persistedReadFromStore() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        try "abc-1234".write(to: env.sessionIDStore, atomically: true, encoding: .utf8)
        let session = env.makeSession()
        #expect(session.conversationID == "abc-1234")
    }

    // MARK: - restart()

    @Test("restart() from .exited transitions to .starting and bumps restartEpoch")
    func restartBumpsEpoch() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        session.markExited(code: 1)
        let priorEpoch = session.restartEpoch
        session.restart()
        guard case .starting = session.state else {
            Issue.record("Expected .starting after restart, got \(session.state)")
            return
        }
        #expect(session.restartEpoch == priorEpoch &+ 1)
    }

    @Test("restart() from .running is a no-op")
    func restartFromRunningIsNoOp() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        let priorEpoch = session.restartEpoch
        let snapshot = session.state
        session.restart()
        #expect(session.state == snapshot)
        #expect(session.restartEpoch == priorEpoch)
    }

    @Test("restart() from .idle is a no-op")
    func restartFromIdleIsNoOp() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        let priorEpoch = session.restartEpoch
        session.restart()
        #expect(session.state == .idle)
        #expect(session.restartEpoch == priorEpoch)
    }

    // MARK: - stopHandler

    @Test("stop() fires registered stopHandler exactly once")
    func stopFiresHandler() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        var fired = 0
        session.registerStopHandler { fired += 1 }
        session.stop()
        #expect(fired == 1)
        // Second stop() is a no-op (state is .exited), handler stays untouched.
        session.stop()
        #expect(fired == 1)
    }

    @Test("clearStopHandler prevents stop() from firing")
    func clearStopHandler() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.attach()
        session.markStarted()
        var fired = 0
        session.registerStopHandler { fired += 1 }
        session.clearStopHandler()
        session.stop()
        #expect(fired == 0)
    }

    @Test("stop() from .idle does not fire stopHandler")
    func stopIdleSkipsHandler() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        var fired = 0
        session.registerStopHandler { fired += 1 }
        session.stop()
        #expect(fired == 0)
    }

    // MARK: - rebuilt(for:replacing:)

    @Test("rebuilt with same cwd returns the same instance")
    func rebuiltSameCwdShortCircuits() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let prior = env.makeSession()
        let rebuilt = TerminalClaudeSession.rebuilt(for: prior.cwd, replacing: prior)
        #expect(rebuilt === prior)
    }

    @Test("rebuilt with different cwd stops prior and returns a fresh session")
    func rebuiltDifferentCwdReplaces() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let prior = env.makeSession()
        prior.attach()
        prior.markStarted()
        var stopFired = 0
        prior.registerStopHandler { stopFired += 1 }
        let otherCwd = env.cwdRoot.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherCwd, withIntermediateDirectories: true)
        let rebuilt = TerminalClaudeSession.rebuilt(for: otherCwd, replacing: prior)
        #expect(rebuilt !== prior)
        #expect(rebuilt.cwd == otherCwd)
        #expect(stopFired == 1)
        // Prior is now .exited; rebuilt is fresh .idle.
        #expect(rebuilt.state == .idle)
    }

    // MARK: - Helpers

    @MainActor
    private struct TempEnv {
        let cwdRoot: URL
        let sessionIDStore: URL
        let sessionLogRoot: URL
        let fakeBinary: URL

        static func make() throws -> TempEnv {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("TerminalClaudeSessionTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return TempEnv(
                cwdRoot: base,
                sessionIDStore: base.appendingPathComponent("session-id"),
                sessionLogRoot: base.appendingPathComponent("claude-projects"),
                fakeBinary: URL(filePath: "/usr/bin/true")
            )
        }

        func makeSession() -> TerminalClaudeSession {
            TerminalClaudeSession(
                cwd: cwdRoot,
                binaryURL: fakeBinary,
                sessionIDStoreOverride: sessionIDStore,
                sessionLogRoot: sessionLogRoot
            )
        }

        func writeClaudeSessionLog(for conversationID: String) throws {
            let encoded = cwdRoot.path.replacingOccurrences(of: "/", with: "-")
            let dir = sessionLogRoot.appendingPathComponent(encoded)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(conversationID).jsonl")
            try "".write(to: file, atomically: true, encoding: .utf8)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: cwdRoot)
        }
    }
}
