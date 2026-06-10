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
            case .userClosed: return "userClosed"
            case .crashed: return "crashed"
            case .killed: return "killed"
            }
        }
    }

    struct ChatMessage: Sendable, Equatable, Identifiable {
        let id: UUID
        let role: Role
        let text: String
        let timestamp: Date

        enum Role: Sendable, Equatable {
            case user
            case assistant
            case system
        }
    }

    let cwd: URL
    let binaryURL: URL
    let modelChoice: ModelChoice
    private let autoSpawn: Bool
    private let sessionLogRoot: URL
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
    private var subcommandTask: Task<Void, Never>?

    // Defaults to ~/.claude/projects but is injectable so tests can point at
    // a temp directory and exercise resumeOrInitArgs / rehydrate without
    // polluting the real home. sessionIDStoreOverride is the per-project
    // file that persists the conversation UUID across project re-opens —
    // mirror to TerminalClaudeSession so chat mode also resumes its claude
    // session via --resume <uuid>. stateDirectory is the resolved project
    // bundle (`<name>.plumage`); the chat-id store lives under its
    // `sessions/` subfolder. CCI stays free of bundle resolution — the
    // caller (ProjectWindow) resolves it once and passes it in.
    init(
        cwd: URL,
        binaryURL: URL,
        stateDirectory: URL,
        modelChoice: ModelChoice = .default,
        autoSpawn: Bool = true,
        sessionLogRoot: URL? = nil,
        sessionIDStoreOverride: URL? = nil,
        rehydrationCap: Int = ClaudeSession.defaultRehydrationCap
    ) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.modelChoice = modelChoice
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

        if let persisted = Self.loadPersistedID(from: storeURL) {
            self.conversationID = persisted
        } else {
            let fresh = UUID().uuidString.lowercased()
            self.conversationID = fresh
            Self.persistID(fresh, to: storeURL)
        }
    }

    // Safety net for abnormal teardown paths (scene killed, owner replaced
    // without explicit stop()). The owning view's .onDisappear is the
    // primary cleanup path; without this deinit a window-close path that
    // skips that hook would leak readTask + stdout fd-pair indefinitely.
    //
    // isolated deinit (Swift 6.2) so we can touch the @MainActor state
    // directly. Practically every release path lands on the main actor
    // anyway (SwiftUI @State on MainActor) — the explicit isolation just
    // makes the compiler happy without an assumeIsolated escape hatch.
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

    // Helper for ProjectWindow's URL-change path: if the new URL matches the
    // existing session's cwd, keeps the session; otherwise stops the prior
    // and returns a fresh ClaudeSession bound to the new cwd. Centralises
    // the binary-location lookup so the call site doesn't duplicate it.
    static func rebuilt(
        for handleURL: URL,
        replacing prior: ClaudeSession,
        stateDirectory: URL,
        modelChoice: ModelChoice? = nil
    ) -> ClaudeSession {
        let newChoice = modelChoice ?? prior.modelChoice
        if prior.cwd == handleURL && prior.modelChoice == newChoice { return prior }
        prior.stop()
        let binary =
            (try? ProductionProcessRunner.locateBinary())
            ?? URL(filePath: "/dev/null")
        return ClaudeSession(
            cwd: handleURL, binaryURL: binary, stateDirectory: stateDirectory,
            modelChoice: newChoice)
    }

    // Repoints where the conversation id is persisted after the project bundle
    // was renamed. The bundle folder moved on disk and carried its `sessions/
    // chat-id` along atomically, so the in-memory conversationID is still valid
    // and only FUTURE persistID writes need the new path. The running subprocess
    // (cwd = project root, log keyed by root — both unchanged) is untouched, so
    // the live chat keeps going. Recomputes the store path the same way init
    // does from the new bundle (stateDirectory).
    func repointSessionStore(toBundle bundle: URL) {
        sessionIDStoreURL =
            bundle
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("chat-id")
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if Self.looksLikeLocalCommand(trimmed) {
            handleLocalSlashCommand(trimmed)
            return
        }

        await sendUserMessage(trimmed)
    }

    private func sendUserMessage(_ trimmed: String) async {
        guard case .running = state else { return }
        messages.append(
            ChatMessage(id: UUID(), role: .user, text: trimmed, timestamp: .now)
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

    // A Plumage slash command is a single leading-slash token with no further
    // path separators ("/clear", "/mcp"). A Finder-dropped absolute path
    // ("/Users/me/notes.txt") also starts with "/" but carries interior slashes,
    // so route those to claude as a normal message instead of bouncing them off
    // handleLocalSlashCommand as an "unknown command". A bare root-level file
    // ("/notes.txt") is the rare exception we accept — Finder paths are
    // effectively always under /Users, /Volumes, etc.
    private nonisolated static func looksLikeLocalCommand(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("/") else { return false }
        let firstToken =
            trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        return !firstToken.dropFirst().contains("/")
    }

    func handleLocalSlashCommand(_ text: String) {
        let command = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
        switch command.lowercased() {
        case "/clear", "/restart":
            clearAndRestart()
        case "/exit", "/quit":
            stop()
        case "/status":
            appendSystemMessage(statusReport())
        case "/mcp":
            appendSystemMessage("Listing MCP servers…")
            // Tracked so stop()/clearAndRestart() teardown can cancel the
            // child via dispatchSubcommand's withTaskCancellationHandler.
            // Cancelling any prior tracked subcommand prevents two slash
            // commands from racing for the slot.
            subcommandTask?.cancel()
            subcommandTask = Task { [weak self] in
                await self?.dispatchSubcommand(["mcp", "list"], label: "MCP servers")
            }
        case "/doctor":
            appendSystemMessage("Running claude doctor…")
            subcommandTask?.cancel()
            subcommandTask = Task { [weak self] in
                await self?.dispatchSubcommand(["doctor"], label: "claude doctor")
            }
        case "/help":
            appendSystemMessage(
                """
                Plumage commands:
                  /clear     Clear chat and restart the claude session
                  /restart   Same as /clear
                  /exit      End the claude session
                  /status    Show current session info
                  /mcp       List configured MCP servers
                  /doctor    Run claude doctor health check
                  /help      Show this message

                Other claude slash commands (e.g. /resume, /login, /model) only \
                work in the interactive REPL — switch to Terminal mode for those.
                """
            )
        default:
            appendSystemMessage(
                """
                Unknown command: \(command). Plumage knows /clear, /restart, \
                /exit, /status, /mcp, /doctor, /help. For claude's own REPL \
                commands switch to Terminal mode.
                """
            )
        }
    }

    private func statusReport() -> String {
        let stateString: String
        switch state {
        case .idle: stateString = "idle"
        case .starting: stateString = "starting"
        case .running(let sid):
            stateString = "running" + (sid.map { " (claude session: \($0))" } ?? "")
        case .exited(let code, let reason): stateString = "ended (exit \(code), \(reason))"
        }
        return """
            Conversation ID: \(conversationID)
            State: \(stateString)
            Messages: \(messages.count)
            Working directory: \(cwd.path)
            """
    }

    private func dispatchSubcommand(_ args: [String], label: String) async {
        let binary = binaryURL
        let workingDirectory = cwd
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        // Await exit via terminationHandler, not waitUntilExit() — the latter
        // deadlocks on the Swift cooperative pool. Reuses ProcessRunning's
        // ClaudeProcessTermination.
        let termination = ClaudeProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            appendSystemMessage("\(label):\nError: \(error.localizedDescription)")
            return
        }

        // withTaskCancellationHandler: if the surrounding session is torn
        // down (handOff / stop / clearAndRestart cancels this Task), send
        // SIGTERM right away so the exit-await resolves instead of pinning
        // a cooperative thread indefinitely. Matches ProductionProcessRunner.
        let output: String = await withTaskCancellationHandler {
            // Drain the shared stdout/stderr pipe in parallel with the exit-await,
            // not after it: a subcommand emitting more than the ~64 KB pipe buffer
            // before exit would block on write() and never terminate if we only
            // read post-exit. Off the cooperative pool — readToEnd() is a blocking
            // syscall. Matches the parallel-drain shape in ProductionProcessRunner.
            async let data = Task.detached { () -> Data in
                (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            }.value
            _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                termination.attach(continuation)
            }
            let text =
                String(data: await data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "(no output)" : text
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
        if Task.isCancelled { return }
        appendSystemMessage("\(label):\n\(output)")
    }

    private func clearAndRestart() {
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
        Self.persistID(conversationID, to: sessionIDStoreURL)
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
        // Without cancelling readTask the AsyncStream's onTermination never
        // fires, so readabilityHandler keeps stdoutHandle + LineBuffer alive
        // even though the subprocess is gone. handleExit, handOff and
        // clearAndRestart already do this — stop() must too.
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

    // Returns the spawn args for a fresh claude attach: --session-id when the
    // session file doesn't exist yet, --resume otherwise. claude's --session-id
    // is strictly "create new" (its SY_ check rejects with "Session ID …
    // already in use" if the .jsonl file is present), so we cannot blindly
    // pass --session-id on every spawn.
    func resumeOrInitArgs() -> [String] {
        guard sessionLogExists() else {
            return ["--session-id", conversationID]
        }
        return ["--resume", conversationID]
    }

    private func sessionLogExists() -> Bool {
        FileManager.default.fileExists(atPath: sessionLogURL().path)
    }

    private func sessionLogURL() -> URL {
        // `/` → `-` mirrors claude CLI's own session-log encoding scheme so
        // Plumage finds the same .jsonl file claude writes. Two paths with
        // `-` in directory names could theoretically collide post-encoding
        // (`/a/b-c/d` and `/a/b/c-d` both produce `-a-b-c-d`), but matching
        // claude's behaviour is the contract — diverging here would just
        // silently break rehydration. Keep in sync if claude ever changes
        // its scheme.
        let encoded = cwd.path.replacingOccurrences(of: "/", with: "-")
        return
            sessionLogRoot
            .appendingPathComponent(encoded)
            .appendingPathComponent("\(conversationID).jsonl")
    }

    // Parse claude's saved session log and replace `messages` with what was
    // exchanged across previous runs (including terminal-mode turns Plumage
    // never observed on its own stdout stream). Called from spawn() so chat
    // mode always reflects the full conversation regardless of which mode it
    // happened in.
    //
    // Skips when `messages` is already populated for this conversationID —
    // the in-memory list is the live source after the first hydration and a
    // second spawn (mode toggle within the same conversation) would just
    // re-read an ever-larger JSONL file for no benefit. /clear regenerates
    // conversationID and resets `messages`, which forces the next spawn to
    // rehydrate the (then-empty-from-our-side) fresh session.
    nonisolated static let defaultRehydrationCap = 200
    // Internal (not private) so tests can drive rehydrate against an injected
    // sessionLogRoot tempdir without spinning up a real subprocess. Production
    // call site stays inside spawn().
    //
    // Disk I/O runs on a detached cooperative task so a slow filesystem
    // (NFS, external SSD) can't block the main thread while the session log
    // is read. The decode pass is also off-actor — the file can be hundreds
    // of KB for long conversations.
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

    // Explicit list, not a generic "<" heuristic — a real user message may
    // start with markup and must survive rehydration.
    nonisolated private static let machineWrapperPrefixes = [
        "<command-", "<local-command-",
        "<bash-input>", "<bash-stdout>", "<bash-stderr>",
        "<system-reminder>",
    ]

    nonisolated private static func parseSessionLog(at file: URL, cap: Int) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: file),
            let raw = String(data: data, encoding: .utf8)
        else { return [] }

        var hydrated: [ChatMessage] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            // claude logs many side-streams (hooks, snapshots, sidechain).
            if json["isSidechain"] as? Bool == true { continue }
            if json["attachment"] != nil { continue }
            guard let type = json["type"] as? String,
                let message = json["message"] as? [String: Any]
            else { continue }
            let role: ChatMessage.Role
            switch type {
            case "user": role = .user
            case "assistant": role = .assistant
            default: continue
            }
            guard let text = Self.extractText(from: message["content"]),
                !text.isEmpty
            else { continue }
            // Drop only the known wrapper payloads — a user message that
            // merely starts with markup must survive rehydration.
            if Self.machineWrapperPrefixes.contains(where: text.hasPrefix) { continue }
            hydrated.append(
                ChatMessage(id: UUID(), role: role, text: text, timestamp: .now)
            )
        }
        // Bound the in-memory list — sessions can grow into thousands of
        // turns and we only need the recent tail to keep the conversation
        // legible in chat mode.
        return Array(hydrated.suffix(cap))
    }

    private nonisolated static func extractText(from content: Any?) -> String? {
        if let str = content as? String { return str }
        if let array = content as? [[String: Any]] {
            let texts = array.compactMap { item -> String? in
                guard let type = item["type"] as? String, type == "text",
                    let text = item["text"] as? String
                else { return nil }
                return text
            }
            return texts.joined(separator: "\n")
        }
        return nil
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
        case .result:
            guard case .running = state else { return }
            awaitingResponse = false
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
        // resumeOrInitArgs chooses --session-id vs --resume based on whether
        // the session log already exists, mirroring claude's own behaviour.
        newProcess.arguments =
            [
                "--print",
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                "--verbose",
            ] + resumeOrInitArgs() + modelChoice.cliArg
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
        // Rehydrate from the on-disk log so chat mode reflects whatever the
        // terminal-mode subprocess wrote since last time. Async + detached
        // so a slow filesystem can't block the main thread while spawn()
        // returns. Safe even on the first spawn (no file → no-op).
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

    // @unchecked Sendable: `partial` is mutated from two contexts —
    // `readabilityHandler` on the FileHandle's background queue (append /
    // flush during streaming) and the AsyncStream's onTermination on
    // teardown. NSLock serializes every read and write of `partial`, so
    // concurrent access is safe even though the compiler can't see it.
    // Removing the lock or relaxing the contract would re-introduce a
    // silent data race on the partial-line buffer.
    //
    // Buffers raw bytes and splits on 0x0A before decoding: decoding whole
    // chunks drops the entire chunk when a multi-byte UTF-8 character spans
    // a chunk boundary (String(data:encoding:) returns nil mid-character).
    // Internal (not private) so tests can pin the chunk-split behavior.
    nonisolated final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var partial = Data()

        func append(_ data: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            partial.append(data)
            var lines: [String] = []
            // Most stdout chunks carry zero or one newline; preallocate
            // for the common case so a streaming burst doesn't trip the
            // array's growth doubling on every chunk.
            lines.reserveCapacity(4)
            while let nl = partial.firstIndex(of: 0x0A) {
                lines.append(
                    String(decoding: partial[partial.startIndex..<nl], as: UTF8.self))
                partial.removeSubrange(partial.startIndex...nl)
            }
            return lines
        }

        func flush() -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard !partial.isEmpty else { return nil }
            let remaining = String(decoding: partial, as: UTF8.self)
            partial = Data()
            return remaining
        }
    }

    private func appendSystemMessage(_ text: String) {
        appendMessage(
            ChatMessage(id: UUID(), role: .system, text: text, timestamp: .now)
        )
    }

    private func appendAssistant(_ content: AssistantContent) {
        switch content {
        case .text(let text):
            appendMessage(
                ChatMessage(id: UUID(), role: .assistant, text: text, timestamp: .now)
            )
        case .toolUse(let name):
            appendMessage(
                ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    text: "🔧 Tool: \(name)",
                    timestamp: .now
                )
            )
        case .other:
            break
        }
    }

    // Cap the live messages array to `rehydrationCap` (with a 2× slack so
    // we only trim in bursts, not on every append). The rehydration path
    // already truncates to the same cap; without this guard a long session
    // with many tool-use turns grows unbounded, slowing ForEach diffs and
    // memory in lockstep.
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
            case SIGTERM, SIGKILL, SIGINT, SIGHUP: return .killed
            default: return .crashed
            }
        default:
            return code == 0 ? .userClosed : .crashed
        }
    }

    private nonisolated static func loadPersistedID(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return raw
    }

    private nonisolated static func persistID(_ id: String, to url: URL) {
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        try? id.write(to: url, atomically: true, encoding: .utf8)
    }
}
