import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ClaudeSession state machine", .serialized)
struct ClaudeSessionTests {
    @Test("starts in .idle")
    func initialState() {
        let session = makeSession()
        #expect(session.state == .idle)
        #expect(session.messages.isEmpty)
        #expect(!session.awaitingResponse)
    }

    @Test("start() transitions .idle to .starting(cwd:)")
    func startTransition() {
        let session = makeSession()
        session.start()
        guard case .starting(let cwd) = session.state else {
            Issue.record("Expected .starting, got \(session.state)")
            return
        }
        #expect(cwd == session.cwd)
    }

    @Test("start() from .starting is a no-op")
    func startIdempotent() {
        let session = makeSession()
        session.start()
        let snapshot = session.state
        session.start()
        #expect(session.state == snapshot)
    }

    @Test("systemInit event during .starting transitions to .running(sessionID:)")
    func systemInitTransitionsToRunning() {
        let session = makeSession()
        session.start()
        session.handleEvent(.systemInit(sessionID: "abc-123"))
        #expect(session.state == .running(sessionID: "abc-123"))
    }

    @Test("systemInit when state is .idle does nothing")
    func systemInitIgnoredWhenIdle() {
        let session = makeSession()
        session.handleEvent(.systemInit(sessionID: "x"))
        #expect(session.state == .idle)
    }

    @Test("assistant text event appends assistant message")
    func assistantTextAppends() {
        let session = startedSession()
        session.handleEvent(.assistant([.text("hello")]))
        #expect(session.messages.count == 1)
        #expect(session.messages[0].role == .assistant)
        #expect(session.messages[0].text == "hello")
    }

    @Test("assistant tool_use event appends compact assistant message containing tool name")
    func toolUseAppendsCompactMessage() {
        let session = startedSession()
        session.handleEvent(.assistant([.toolUse(name: "Bash")]))
        #expect(session.messages.count == 1)
        #expect(session.messages[0].role == .assistant)
        #expect(session.messages[0].text.contains("Bash"))
    }

    @Test("assistant event before .running is ignored")
    func assistantIgnoredOutsideRunning() {
        let session = makeSession()
        session.handleEvent(.assistant([.text("nope")]))
        #expect(session.messages.isEmpty)
    }

    @Test("send() during .running appends user message and sets awaiting")
    func sendAppendsUser() async {
        let session = startedSession()
        await session.send("hi there")
        #expect(session.messages.count == 1)
        #expect(session.messages[0].role == .user)
        #expect(session.messages[0].text == "hi there")
        #expect(session.awaitingResponse)
    }

    @Test("send() trims whitespace and skips empty input")
    func sendTrimsAndSkips() async {
        let session = startedSession()
        await session.send("   \n\n  ")
        #expect(session.messages.isEmpty)
        #expect(!session.awaitingResponse)
    }

    @Test("send() outside .running is ignored")
    func sendIgnoredOutsideRunning() async {
        let session = makeSession()
        await session.send("hi")
        #expect(session.messages.isEmpty)
    }

    @Test("/help appends a system message even when not running")
    func slashHelpWorksWhenIdle() async {
        let session = makeSession()
        await session.send("/help")
        #expect(session.messages.count == 1)
        #expect(session.messages[0].role == .system)
        #expect(session.messages[0].text.contains("/clear"))
        #expect(session.messages[0].text.contains("/exit"))
    }

    @Test("unknown slash command produces system feedback")
    func slashUnknownProducesFeedback() async {
        let session = startedSession()
        await session.send("/wat")
        #expect(session.messages.count == 1)
        #expect(session.messages[0].role == .system)
        #expect(session.messages[0].text.lowercased().contains("unknown"))
    }

    @Test("/clear clears messages without leaving claude alive")
    func slashClearResetsMessages() async {
        let session = startedSession()
        await session.send("first")
        session.handleEvent(.assistant([.text("reply")]))
        #expect(session.messages.count == 2)

        await session.send("/clear")
        #expect(session.messages.isEmpty)
        // With autoSpawn:false, state lands back in .starting since no respawn happens.
        guard case .starting = session.state else {
            Issue.record("Expected .starting after /clear, got \(session.state)")
            return
        }
    }

    @Test("/exit triggers stop and emits no user message")
    func slashExitInvokesStop() async {
        let session = startedSession()
        // Seed a prior assistant turn so `messages.isEmpty` actually
        // differentiates "/exit did not emit" from "we started empty".
        session.handleEvent(.assistant([.text("reply")]))
        #expect(session.messages.count == 1)

        await session.send("/exit")
        // /exit itself does not produce a user message…
        #expect(session.messages.count == 1)
        // …and state stays .running until the terminationHandler fires (which
        // never does in this autoSpawn:false test — no real process exists).
        #expect(session.state == .running(sessionID: "test-session"))
    }

    @Test("result event clears awaitingResponse")
    func resultClearsAwaiting() async {
        let session = startedSession()
        await session.send("hi")
        #expect(session.awaitingResponse)
        session.handleEvent(.result(isError: false, text: "done"))
        #expect(!session.awaitingResponse)
    }

    @Test("handleExit(0) from .running yields .exited(0, .userClosed)")
    func exitZeroIsUserClosed() {
        let session = startedSession()
        session.handleExit(code: 0)
        #expect(session.state == .exited(code: 0, reason: .userClosed))
    }

    @Test("handleExit(137) yields .exited(137, .killed) for signal codes")
    func exitKilledSignal() {
        let session = startedSession()
        session.handleExit(code: 137)
        #expect(session.state == .exited(code: 137, reason: .killed))
    }

    @Test("handleExit(1) yields .exited(1, .crashed) for non-zero non-signal codes")
    func exitNonZeroCrashed() {
        let session = startedSession()
        session.handleExit(code: 1)
        #expect(session.state == .exited(code: 1, reason: .crashed))
    }

    @Test("handleExit during .starting still transitions to .exited")
    func exitDuringStarting() {
        let session = makeSession()
        session.start()
        session.handleExit(code: 0)
        #expect(session.state == .exited(code: 0, reason: .userClosed))
    }

    @Test("handleExit when .idle is ignored")
    func exitIgnoredWhenIdle() {
        let session = makeSession()
        session.handleExit(code: 0)
        #expect(session.state == .idle)
    }

    @Test("restart() from .exited transitions to .starting and keeps messages")
    func restartFromExited() async {
        let session = startedSession()
        await session.send("hi")
        session.handleEvent(.assistant([.text("hello")]))
        session.handleExit(code: 1)
        #expect(session.messages.count == 2)
        let beforeRestartID = session.conversationID

        session.restart()
        guard case .starting = session.state else {
            Issue.record("Expected .starting after restart, got \(session.state)")
            return
        }
        // restart keeps the same conversation — both messages and ID survive.
        #expect(session.messages.count == 2)
        #expect(!session.awaitingResponse)
        #expect(session.conversationID == beforeRestartID)
    }

    @Test("/clear regenerates conversationID and clears messages")
    func slashClearRegeneratesConversationID() async {
        let session = startedSession()
        await session.send("first")
        let originalID = session.conversationID
        await session.send("/clear")
        #expect(session.messages.isEmpty)
        #expect(session.conversationID != originalID)
    }

    @Test("restart() from .running is a no-op")
    func restartFromRunningIsNoOp() {
        let session = startedSession()
        let snapshot = session.state
        session.restart()
        #expect(session.state == snapshot)
    }

    @Test("restart() from .idle is a no-op")
    func restartFromIdleIsNoOp() {
        let session = makeSession()
        session.restart()
        #expect(session.state == .idle)
    }

    // MARK: - awaitHandOff

    @Test("awaitHandOff returns immediately when not pending")
    func awaitHandOffEarlyExit() async {
        let session = makeSession()
        let start = ContinuousClock().now
        await session.awaitHandOff(timeout: .seconds(1))
        let elapsed = ContinuousClock().now - start
        // No suspension expected — should be well under the timeout.
        #expect(elapsed < .milliseconds(100))
    }

    @Test("awaitHandOff resolves when markExternalHandOffDone fires")
    func awaitHandOffResolvesOnSignal() async {
        let session = makeSession()
        session.beginExternalHandOff()
        #expect(session.handOffPending)

        let waiter = Task { @MainActor in
            await session.awaitHandOff(timeout: .seconds(2))
        }

        // Yield so the waiter Task registers its continuation before we signal.
        try? await Task.sleep(for: .milliseconds(20))
        session.markExternalHandOffDone()

        await waiter.value
        #expect(!session.handOffPending)
    }

    @Test("awaitHandOff returns after timeout when no signal arrives")
    func awaitHandOffTimesOut() async {
        let session = makeSession()
        session.beginExternalHandOff()

        let start = ContinuousClock().now
        await session.awaitHandOff(timeout: .milliseconds(100))
        let elapsed = ContinuousClock().now - start

        #expect(elapsed >= .milliseconds(80))
        #expect(elapsed < .seconds(1))
        // Timeout doesn't clear the flag — only an external signal does.
        #expect(session.handOffPending)
    }

    // MARK: - resumeOrInitArgs

    @Test("resumeOrInitArgs returns --session-id when log absent")
    func resumeArgsNewSession() throws {
        let temp = try makeTempLogRoot()
        defer { try? FileManager.default.removeItem(at: temp) }
        let session = makeSession(cwd: URL(filePath: "/tmp/proj"), sessionLogRoot: temp)

        let args = session.resumeOrInitArgs()
        #expect(args.count == 2)
        #expect(args[0] == "--session-id")
        #expect(args[1] == session.conversationID)
    }

    @Test("resumeOrInitArgs returns --resume when log exists")
    func resumeArgsExistingSession() throws {
        let temp = try makeTempLogRoot()
        defer { try? FileManager.default.removeItem(at: temp) }
        let cwd = URL(filePath: "/tmp/proj")
        let session = makeSession(cwd: cwd, sessionLogRoot: temp)
        try writeSessionLog(at: temp, cwd: cwd, conversationID: session.conversationID, contents: "")

        let args = session.resumeOrInitArgs()
        #expect(args.count == 2)
        #expect(args[0] == "--resume")
        #expect(args[1] == session.conversationID)
    }

    // MARK: - rehydrateMessagesFromSessionLog

    @Test("rehydrate is a no-op when session log does not exist")
    func rehydrateMissingLog() async throws {
        let temp = try makeTempLogRoot()
        defer { try? FileManager.default.removeItem(at: temp) }
        let session = makeSession(cwd: URL(filePath: "/tmp/proj"), sessionLogRoot: temp)

        await session.rehydrateMessagesFromSessionLog()
        #expect(session.messages.isEmpty)
    }

    @Test("rehydrate parses user and assistant turns")
    func rehydrateBasicTurns() async throws {
        let temp = try makeTempLogRoot()
        defer { try? FileManager.default.removeItem(at: temp) }
        let cwd = URL(filePath: "/tmp/proj")
        let session = makeSession(cwd: cwd, sessionLogRoot: temp)
        let jsonl = """
            {"type":"user","message":{"role":"user","content":"hi"}}
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}
            """
        try writeSessionLog(
            at: temp, cwd: cwd, conversationID: session.conversationID, contents: jsonl)

        await session.rehydrateMessagesFromSessionLog()
        #expect(session.messages.count == 2)
        #expect(session.messages[0].role == .user)
        #expect(session.messages[0].text == "hi")
        #expect(session.messages[1].role == .assistant)
        #expect(session.messages[1].text == "hello")
    }

    @Test("rehydrate skips sidechain, attachments, and <command-…> wrappers")
    func rehydrateFilters() async throws {
        let temp = try makeTempLogRoot()
        defer { try? FileManager.default.removeItem(at: temp) }
        let cwd = URL(filePath: "/tmp/proj")
        let session = makeSession(cwd: cwd, sessionLogRoot: temp)
        let jsonl = """
            {"type":"user","isSidechain":true,"message":{"role":"user","content":"sidechain"}}
            {"type":"user","attachment":{"path":"x"},"message":{"role":"user","content":"file"}}
            {"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}
            {"type":"user","message":{"role":"user","content":"real turn"}}
            """
        try writeSessionLog(
            at: temp, cwd: cwd, conversationID: session.conversationID, contents: jsonl)

        await session.rehydrateMessagesFromSessionLog()
        #expect(session.messages.count == 1)
        #expect(session.messages[0].text == "real turn")
    }

    @Test("rehydrate is a no-op when messages are already populated")
    func rehydrateSkipsWhenPopulated() async throws {
        let temp = try makeTempLogRoot()
        defer { try? FileManager.default.removeItem(at: temp) }
        let cwd = URL(filePath: "/tmp/proj")
        let session = makeSession(cwd: cwd, sessionLogRoot: temp)
        // Seed in-memory messages and a different log on disk.
        session.start()
        session.handleEvent(.systemInit(sessionID: "test"))
        session.handleEvent(.assistant([.text("in memory")]))
        #expect(session.messages.count == 1)
        let jsonl =
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on disk"}]}}"#
        try writeSessionLog(
            at: temp, cwd: cwd, conversationID: session.conversationID, contents: jsonl)

        await session.rehydrateMessagesFromSessionLog()
        #expect(session.messages.count == 1)
        #expect(session.messages[0].text == "in memory")
    }

    @Test("rehydrate caps to ClaudeSession.defaultRehydrationCap most recent turns")
    func rehydrateCapsToTail() async throws {
        let temp = try makeTempLogRoot()
        defer { try? FileManager.default.removeItem(at: temp) }
        let cwd = URL(filePath: "/tmp/proj")
        let session = makeSession(cwd: cwd, sessionLogRoot: temp)
        let totalTurns = ClaudeSession.defaultRehydrationCap + 50
        let lines = (0..<totalTurns).map { index in
            #"{"type":"user","message":{"role":"user","content":"turn \#(index)"}}"#
        }
        try writeSessionLog(
            at: temp, cwd: cwd, conversationID: session.conversationID,
            contents: lines.joined(separator: "\n"))

        await session.rehydrateMessagesFromSessionLog()
        #expect(session.messages.count == ClaudeSession.defaultRehydrationCap)
        // Tail-kept: first kept turn is turn 50, last kept is turn (totalTurns-1).
        #expect(session.messages.first?.text == "turn 50")
        #expect(session.messages.last?.text == "turn \(totalTurns - 1)")
    }

    // MARK: - Helpers

    private func makeSession(
        cwd: URL = URL(filePath: "/tmp"),
        sessionLogRoot: URL? = nil
    ) -> ClaudeSession {
        ClaudeSession(
            cwd: cwd,
            binaryURL: URL(filePath: "/usr/bin/true"),
            autoSpawn: false,
            sessionLogRoot: sessionLogRoot
        )
    }

    private func startedSession() -> ClaudeSession {
        let session = makeSession()
        session.start()
        session.handleEvent(.systemInit(sessionID: "test-session"))
        return session
    }

    private func makeTempLogRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSessionLog(
        at root: URL, cwd: URL, conversationID: String, contents: String
    ) throws {
        let encoded = cwd.path.replacingOccurrences(of: "/", with: "-")
        let projectDir = root.appendingPathComponent(encoded)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let file = projectDir.appendingPathComponent("\(conversationID).jsonl")
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }
}
