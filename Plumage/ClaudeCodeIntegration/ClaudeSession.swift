import Foundation
import Observation
import os

@Observable
@MainActor
final class ClaudeSession {
    private static let logger = Logger(subsystem: "com.plumage", category: "ClaudeSession")

    enum State: Sendable, Equatable {
        case idle
        case starting(cwd: URL)
        case running(sessionID: String?)
        case exited(code: Int32, reason: ExitReason)
    }

    enum ExitReason: Sendable, Equatable {
        case userClosed
        case crashed
        case killed

        var displayName: String {
            switch self {
            case .userClosed: "userClosed"
            case .crashed: "crashed"
            case .killed: "killed"
            }
        }
    }

    struct ChatMessage: Sendable, Equatable, Identifiable {
        let id: UUID
        let role: Role
        let text: String

        enum Role: Sendable, Equatable {
            case user
            case assistant
            case system
        }
    }

    let cwd: URL
    let binaryURL: URL
    let modelChoice: ModelChoice
    let effortChoice: EffortLevel
    private let autoSpawn: Bool
    let sessionLogRoot: URL
    // var, not let: a project rename moves the bundle folder, so the
    // bundle-derived chat-id store path changes. repointSessionStore updates it
    // for future writes without disturbing the running subprocess.
    private(set) var sessionIDStoreURL: URL
    private let rehydrationCap: Int

    private(set) var state: State = .idle
    private(set) var messages: [ChatMessage] = []
    private(set) var awaitingResponse: Bool = false
    // Hoisted out of ChatView so the input buffer survives panel re-mounts
    // when the dock toggles between button and panel via glassEffectID-morph.
    var draftMessage: String = ""
    private(set) var conversationID: String

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    var subcommandTask: Task<Void, Never>?

    // sessionLogRoot is injectable so tests avoid the real home. The chat-id store
    // under stateDirectory's `sessions/` persists the conversation UUID across
    // re-opens (--resume), mirroring TerminalClaudeSession; the caller resolves the bundle.
    init(
        cwd: URL,
        binaryURL: URL,
        stateDirectory: URL,
        modelChoice: ModelChoice = .default,
        effortChoice: EffortLevel = .default,
        autoSpawn: Bool = true,
        sessionLogRoot: URL? = nil,
        sessionIDStoreOverride: URL? = nil,
        rehydrationCap: Int = ClaudeSession.defaultRehydrationCap
    ) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.modelChoice = modelChoice
        self.effortChoice = effortChoice
        self.autoSpawn = autoSpawn
        self.rehydrationCap = rehydrationCap
        self.sessionLogRoot =
            sessionLogRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        // Local first, then assign: sessionIDStoreURL is now a `var`, and
        // reading `self.<var>` during init (before conversationID is set)
        // trips definite-initialization. The local sidesteps that.
        let storeURL =
            sessionIDStoreOverride
            ?? stateDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("chat-id")
        self.sessionIDStoreURL = storeURL

        if let persisted = ClaudeSessionStorage.loadPersistedID(from: storeURL) {
            self.conversationID = persisted
        } else {
            let fresh = UUID().uuidString.lowercased()
            self.conversationID = fresh
            ClaudeSessionStorage.persistID(fresh, to: storeURL)
        }
    }

    // Safety net for abnormal teardown: a window-close that skips .onDisappear
    // would leak readTask + the stdout fd-pair indefinitely. isolated deinit
    // (Swift 6.2) so @MainActor state is touchable without assumeIsolated.
    isolated deinit {
        readTask?.cancel()
        subcommandTask?.cancel()
        try? stdinHandle?.close()
        process?.terminate()
    }

    func start() {
        guard case .idle = state else { return }
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    // Window-scoped lifecycle hook called from ProjectWindow.task. Picks the
    // right transition for the session's current state (start vs restart vs
    // no-op) so the view body stays free of state-machine logic.
    func attach() {
        switch state {
        case .idle: start()
        case .exited: restart()
        case .starting, .running: break
        }
    }

    // ProjectWindow URL-change path: keeps the session if the new URL matches its
    // cwd, else stops the prior and returns a fresh one bound to the new cwd.
    // Centralises the binary-location lookup so the call site doesn't duplicate it.
    static func rebuilt(
        for handleURL: URL,
        replacing prior: ClaudeSession,
        stateDirectory: URL,
        modelChoice: ModelChoice? = nil,
        effortChoice: EffortLevel? = nil
    ) -> ClaudeSession {
        let newChoice = modelChoice ?? prior.modelChoice
        let newEffort = effortChoice ?? prior.effortChoice
        if prior.cwd == handleURL && prior.modelChoice == newChoice
            && prior.effortChoice == newEffort
        {
            return prior
        }
        prior.stop()
        let binary =
            (try? ProductionProcessRunner.locateBinary())
            ?? URL(filePath: "/dev/null")
        return ClaudeSession(
            cwd: handleURL, binaryURL: binary, stateDirectory: stateDirectory,
            modelChoice: newChoice, effortChoice: newEffort)
    }

    // Repoint persistence after a bundle rename: the folder moved atomically with
    // its `sessions/chat-id`, so the in-memory conversationID stays valid and only
    // FUTURE persistID writes need the new path; the running subprocess is untouched.
    func repointSessionStore(toBundle bundle: URL) {
        sessionIDStoreURL =
            bundle
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("chat-id")
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if handleIfLocalCommand(trimmed) { return }

        await sendUserMessage(trimmed)
    }

    private func sendUserMessage(_ trimmed: String) async {
        guard case .running = state else { return }
        messages.append(
            ChatMessage(id: UUID(), role: .user, text: trimmed)
        )
        awaitingResponse = true

        guard let handle = stdinHandle else { return }
        do {
            let data = try ClaudeMessageEncoding.encode(userText: trimmed)
            try handle.write(contentsOf: data)
        } catch {
            appendSystemMessage("Failed to send message: \(error.localizedDescription)")
            awaitingResponse = false
        }
    }

    func clearAndRestart() {
        // Tear down the current process without going through handleExit's
        // state transition — we want to land in .starting → .running directly.
        process?.terminationHandler = nil
        process?.terminate()
        try? stdinHandle?.close()
        stdinHandle = nil
        readTask?.cancel()
        readTask = nil
        subcommandTask?.cancel()
        subcommandTask = nil
        process = nil

        // Fresh context: new session ID, dropped history. Persist so the
        // next project-open's --resume targets the new conversation, not the
        // stale pre-clear one.
        conversationID = UUID().uuidString.lowercased()
        ClaudeSessionStorage.persistID(conversationID, to: sessionIDStoreURL)
        messages = []
        awaitingResponse = false
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    func stop() {
        // Clear the terminationHandler before terminate(): this is a
        // user-initiated stop, and the async handleExit path would race in
        // and reclassify the SIGTERM exit as "crashed"/"killed".
        process?.terminationHandler = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        // Without cancelling readTask the AsyncStream's onTermination never fires,
        // so readabilityHandler keeps stdoutHandle + LineBuffer alive even though
        // the subprocess is gone. handleExit/clearAndRestart do this too.
        readTask?.cancel()
        readTask = nil
        subcommandTask?.cancel()
        subcommandTask = nil
        process?.terminate()
        process = nil
        switch state {
        case .starting, .running:
            state = .exited(code: 0, reason: .userClosed)
        case .idle, .exited:
            break
        }
        awaitingResponse = false
    }

    // Restart keeps messages and conversationID — Banner-Restart resumes the
    // same conversation; only /clear creates a fresh one (see clearAndRestart).
    func restart() {
        guard case .exited = state else { return }
        awaitingResponse = false
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    // Chat carries no theme --settings, so settingsCLIArgs only fills it for ultracode.
    func spawnArguments() -> [String] {
        [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
        ] + resumeOrInitArgs() + modelChoice.cliArg + effortChoice.cliArg
            + effortChoice.settingsCLIArgs
    }

    func resumeOrInitArgs() -> [String] {
        ClaudeSessionStorage.resumeOrInitArgs(
            conversationID: conversationID, logRoot: sessionLogRoot, cwd: cwd)
    }

    // Replaces `messages` from claude's saved session log (incl. terminal-mode
    // turns); skipped once populated — /clear forces a re-read. Internal for
    // tests; disk I/O + decode run detached so they never block the main thread.
    func rehydrateMessagesFromSessionLog() async {
        guard messages.isEmpty else { return }
        let file = sessionLogURL()
        let cap = rehydrationCap
        let hydrated = await Task.detached(priority: .userInitiated) {
            Self.parseSessionLog(at: file, cap: cap)
        }.value
        // After the await: another caller could have populated `messages` in
        // the meantime (e.g., a /clear that landed during the read). Don't
        // clobber a non-empty list with a rehydration of the prior session.
        guard messages.isEmpty, !hydrated.isEmpty else { return }
        messages = hydrated
    }

    func handleEvent(_ event: ClaudeStreamEvent) {
        switch event {
        case .systemInit(let sessionID):
            if case .running = state {
                state = .running(sessionID: sessionID)
            } else if case .starting = state {
                state = .running(sessionID: sessionID)
            }
        case .systemOther, .rateLimit, .unknown:
            break
        case .assistant(let contents):
            guard case .running = state else { return }
            for content in contents {
                appendAssistant(content)
            }
        case .result(let isError, let text):
            guard case .running = state else { return }
            awaitingResponse = false
            // An error result would otherwise vanish silently — the turn just
            // ends with no assistant output and no hint why.
            if isError {
                let detail = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                appendSystemMessage(
                    detail.isEmpty ? "claude reported an error for this turn." : detail)
            }
        }
    }

    func handleExit(code: Int32, reason: Process.TerminationReason = .exit) {
        switch state {
        case .idle, .exited:
            return
        case .starting, .running:
            state = .exited(code: code, reason: Self.classify(code: code, reason: reason))
            awaitingResponse = false
            readTask?.cancel()
            readTask = nil
            try? stdinHandle?.close()
            stdinHandle = nil
            process = nil
        }
    }

    private func spawn() {
        let newProcess = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        newProcess.executableURL = binaryURL
        newProcess.currentDirectoryURL = cwd
        newProcess.arguments = spawnArguments()
        newProcess.standardInput = stdinPipe
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = FileHandle.nullDevice

        newProcess.terminationHandler = { terminated in
            let code = terminated.terminationStatus
            let reason = terminated.terminationReason
            Task { @MainActor [weak self] in
                self?.handleExit(code: code, reason: reason)
            }
        }

        do {
            try newProcess.run()
        } catch {
            state = .exited(code: -1, reason: .crashed)
            appendSystemMessage("Failed to launch claude: \(error.localizedDescription)")
            return
        }

        process = newProcess
        stdinHandle = stdinPipe.fileHandleForWriting
        // Rehydrate from the on-disk log so chat mode reflects what terminal mode
        // wrote since last time. Async + detached so a slow filesystem can't block
        // spawn()'s return. Safe even on the first spawn (no file → no-op).
        Task { @MainActor [weak self] in
            await self?.rehydrateMessagesFromSessionLog()
        }
        // claude emits system/init only after the first user message — the spawn
        // alone proves the process is alive, so move to .running now and let
        // handleEvent fill the sessionID when init eventually arrives.
        state = .running(sessionID: nil)

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let buffer = LineBuffer()
        let stream = AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    if let final = buffer.flush() { continuation.yield(final) }
                    continuation.finish()
                    return
                }
                for line in buffer.append(data) { continuation.yield(line) }
            }
            continuation.onTermination = { _ in
                stdoutHandle.readabilityHandler = nil
            }
        }

        // Hoisted out of the per-line loop: the read loop fires continuously
        // during an active session (tens of events/s on tool-use turns), and a
        // fresh JSONDecoder per line is needless allocation in that hot path.
        let decoder = JSONDecoder()
        readTask = Task { @MainActor [weak self] in
            for await line in stream {
                guard let self else { return }
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8) else { continue }
                do {
                    let event = try decoder.decode(ClaudeStreamEvent.self, from: data)
                    self.handleEvent(event)
                } catch {
                    // --verbose interleaves plain-text lines that are fine to
                    // skip; only `{`-prefixed lines were meant to be events.
                    if line.hasPrefix("{") {
                        Self.logger.warning(
                            "Dropping malformed stream event: \(String(describing: error), privacy: .public)"
                        )
                    }
                }
            }
        }
    }

    func appendSystemMessage(_ text: String) {
        appendMessage(
            ChatMessage(id: UUID(), role: .system, text: text)
        )
    }

    private func appendAssistant(_ content: AssistantContent) {
        switch content {
        case .text(let text):
            appendMessage(
                ChatMessage(id: UUID(), role: .assistant, text: text)
            )
        case .toolUse(let name):
            appendMessage(
                ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    text: "🔧 Tool: \(name)"
                )
            )
        case .other:
            break
        }
    }

    // Cap live messages at rehydrationCap with 2× slack so we trim in bursts, not
    // on every append. Without this a long session with many tool-use turns grows
    // unbounded, slowing ForEach diffs and memory in lockstep.
    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > rehydrationCap * 2 {
            messages = Array(messages.suffix(rehydrationCap))
        }
    }

    // On .uncaughtSignal, terminationStatus carries the raw signal number —
    // the 128+n shell convention never applies to a directly-spawned process,
    // so a plain code-range check misclassifies signal exits.
    nonisolated static func classify(
        code: Int32, reason: Process.TerminationReason
    ) -> ExitReason {
        switch reason {
        case .uncaughtSignal:
            switch code {
            case SIGTERM, SIGKILL, SIGINT, SIGHUP: .killed
            default: .crashed
            }
        default:
            code == 0 ? .userClosed : .crashed
        }
    }
}
