import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ClaudeSession state machine")
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
        if case .starting(let cwd) = session.state {
            #expect(cwd == session.cwd)
        } else {
            Issue.record("Expected .starting, got \(session.state)")
        }
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
        if case .starting = session.state {
            // ok
        } else {
            Issue.record("Expected .starting after /clear, got \(session.state)")
        }
    }

    @Test("/exit triggers stop and leaves session waiting for terminationHandler")
    func slashExitInvokesStop() async {
        let session = startedSession()
        await session.send("/exit")
        // stop() closes stdin; state remains .running until the (non-existent in
        // tests) terminationHandler fires. We assert that no user-message was
        // emitted on stdin (messages stay empty for the /exit command itself).
        #expect(session.messages.isEmpty)
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

    @Test("restart() from .exited transitions to .starting and clears messages")
    func restartFromExited() async {
        let session = startedSession()
        await session.send("hi")
        session.handleEvent(.assistant([.text("hello")]))
        session.handleExit(code: 1)
        #expect(session.messages.count == 2)

        session.restart()
        if case .starting = session.state {
            // OK
        } else {
            Issue.record("Expected .starting after restart, got \(session.state)")
        }
        #expect(session.messages.isEmpty)
        #expect(!session.awaitingResponse)
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

    // MARK: - Helpers

    private func makeSession() -> ClaudeSession {
        ClaudeSession(
            cwd: URL(filePath: "/tmp"),
            binaryURL: URL(filePath: "/usr/bin/true"),
            autoSpawn: false
        )
    }

    private func startedSession() -> ClaudeSession {
        let session = makeSession()
        session.start()
        session.handleEvent(.systemInit(sessionID: "test-session"))
        return session
    }
}
