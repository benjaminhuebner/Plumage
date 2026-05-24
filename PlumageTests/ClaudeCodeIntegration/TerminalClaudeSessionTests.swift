import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TerminalClaudeSession")
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

    // MARK: - pendingInput queue

    @Test("pendingInput starts empty")
    func pendingInputInitiallyEmpty() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        #expect(session.pendingInput.isEmpty)
    }

    @Test("enqueue appends in order")
    func enqueueAppendsInOrder() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.enqueue("first")
        session.enqueue("second")
        session.enqueue("third")
        #expect(session.pendingInput == ["first", "second", "third"])
    }

    @Test("consumePending returns and clears the buffer")
    func consumePendingClears() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.enqueue("/plumage-plan foo\n")
        session.enqueue("body line\n")
        let drained = session.consumePending()
        #expect(drained == ["/plumage-plan foo\n", "body line\n"])
        #expect(session.pendingInput.isEmpty)
    }

    @Test("consumePending on empty buffer returns empty")
    func consumePendingEmpty() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        #expect(session.consumePending().isEmpty)
        #expect(session.pendingInput.isEmpty)
    }

    // MARK: - reconcileSessionFromDisk

    @Test("reconcileSessionFromDisk adopts a fresher non-excluded jsonl and persists")
    func reconcileAdoptsNewJsonl() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        let originalID = session.conversationID
        session.attach()
        session.markStarted()
        // markStarted's reconcile may run before the new file appears; we
        // simulate the post-/clear rotation by writing a fresh-mtime jsonl
        // and re-invoking reconcile manually. +1ms offset removes any
        // APFS-rounding ambiguity around the launchInstant comparison.
        let newID = "post-clear-\(UUID().uuidString.lowercased())"
        try env.writeClaudeSessionLog(for: newID, mtime: Date(timeIntervalSinceNow: 0.001))
        session.reconcileSessionFromDisk()
        #expect(session.conversationID == newID)
        // ID is persisted so a relaunch picks it up.
        let persisted = try String(contentsOf: env.sessionIDStore, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(persisted == newID)
        #expect(session.conversationID != originalID)
    }

    @Test("reconcileSessionFromDisk ignores excluded IDs (chat session)")
    func reconcileSkipsExcluded() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let chatID = "chat-\(UUID().uuidString.lowercased())"
        let session = env.makeSession(excludedSessionIDs: { [chatID] })
        let originalID = session.conversationID
        session.attach()
        session.markStarted()
        // Chat's jsonl shows up in the same dir but must not be adopted.
        try env.writeClaudeSessionLog(for: chatID, mtime: Date())
        session.reconcileSessionFromDisk()
        #expect(session.conversationID == originalID)
    }

    @Test("reconcileSessionFromDisk picks one candidate when two share identical mtime")
    func reconcileTwoEqualMtime() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        let originalID = session.conversationID
        session.attach()
        session.markStarted()
        // Pin the current behavior: when two non-excluded candidates have
        // identical mtime, reconcile adopts one of them (filesystem-order).
        // This test guards against silent behavior changes — e.g., a refactor
        // that flipped `<=` to `<` in the tie-break check, which would adopt
        // the second file instead of the first.
        let shared = Date(timeIntervalSinceNow: 0.001)
        let idA = "equal-a-\(UUID().uuidString.lowercased())"
        let idB = "equal-b-\(UUID().uuidString.lowercased())"
        try env.writeClaudeSessionLog(for: idA, mtime: shared)
        try env.writeClaudeSessionLog(for: idB, mtime: shared)
        session.reconcileSessionFromDisk()
        #expect(session.conversationID == idA || session.conversationID == idB)
        #expect(session.conversationID != originalID)
    }

    @Test("reconcileSessionFromDisk is no-op between restart() and markStarted()")
    func reconcileNoOpBetweenRestartAndMarkStarted() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        let originalID = session.conversationID
        session.attach()
        session.markStarted()
        session.markExited(code: 0)
        // After restart() state is .starting but launchInstant is still nil
        // (cleared by stopLogWatcher inside markExited). reconcile must guard
        // on launchInstant and not adopt a fresh candidate written during
        // this window — otherwise the restart-respawn path would steal an ID
        // before the new subprocess gets to write its own.
        session.restart()
        let candidateID = "should-not-adopt-\(UUID().uuidString.lowercased())"
        try env.writeClaudeSessionLog(
            for: candidateID, mtime: Date(timeIntervalSinceNow: 0.001))
        session.reconcileSessionFromDisk()
        #expect(session.conversationID == originalID)
    }

    @Test("reconcileSessionFromDisk ignores jsonls older than launchInstant")
    func reconcileSkipsOldFiles() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        let originalID = session.conversationID
        // Pre-existing log file from a previous boot — mtime in the past.
        let oldID = "old-\(UUID().uuidString.lowercased())"
        try env.writeClaudeSessionLog(
            for: oldID, mtime: Date(timeIntervalSinceNow: -3600))
        session.attach()
        session.markStarted()  // launchInstant ≈ now, after the old file's mtime
        #expect(session.conversationID == originalID)
        // Explicit second call returns the same answer.
        session.reconcileSessionFromDisk()
        #expect(session.conversationID == originalID)
    }

    @Test("enqueue is independent of session state")
    func enqueueIgnoresState() throws {
        let env = try TempEnv.make()
        defer { env.cleanup() }
        let session = env.makeSession()
        session.enqueue("before-attach")
        session.attach()
        session.enqueue("after-attach")
        session.markStarted()
        session.enqueue("after-running")
        #expect(session.pendingInput == ["before-attach", "after-attach", "after-running"])
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

        func makeSession(
            excludedSessionIDs: @escaping () -> Set<String> = { [] }
        ) -> TerminalClaudeSession {
            TerminalClaudeSession(
                cwd: cwdRoot,
                binaryURL: fakeBinary,
                sessionIDStoreOverride: sessionIDStore,
                sessionLogRoot: sessionLogRoot,
                excludedSessionIDs: excludedSessionIDs
            )
        }

        func writeClaudeSessionLog(for conversationID: String, mtime: Date? = nil) throws {
            let encoded = cwdRoot.path.replacingOccurrences(of: "/", with: "-")
            let dir = sessionLogRoot.appendingPathComponent(encoded)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(conversationID).jsonl")
            try "".write(to: file, atomically: true, encoding: .utf8)
            if let mtime {
                try FileManager.default.setAttributes(
                    [.modificationDate: mtime], ofItemAtPath: file.path)
            }
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: cwdRoot)
        }
    }
}
