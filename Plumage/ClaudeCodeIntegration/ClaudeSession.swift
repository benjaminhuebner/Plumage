import Foundation
import Observation

@Observable
@MainActor
final class ClaudeSession {
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
    private let autoSpawn: Bool

    private(set) var state: State = .idle
    private(set) var messages: [ChatMessage] = []
    private(set) var awaitingResponse: Bool = false
    private(set) var conversationID: String
    // True while a previous claude (chat or terminal) is mid-shutdown and
    // still owns the session-id log lock. The next mode's spawn must wait
    // for this to flip back to false or the new claude exits with
    // "Session ID … is already in use."
    private(set) var handOffPending: Bool = false

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?

    init(cwd: URL, binaryURL: URL, autoSpawn: Bool = true) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.autoSpawn = autoSpawn
        self.conversationID = UUID().uuidString.lowercased()
    }

    func start() {
        guard case .idle = state else { return }
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("/") {
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
            Task { [weak self] in
                await self?.dispatchSubcommand(["mcp", "list"], label: "MCP servers")
            }
        case "/doctor":
            appendSystemMessage("Running claude doctor…")
            Task { [weak self] in
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
        let output = await Task.detached { () -> String in
            let task = Process()
            task.executableURL = binary
            task.arguments = args
            task.currentDirectoryURL = workingDirectory
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            task.standardInput = FileHandle.nullDevice
            do {
                try task.run()
            } catch {
                return "Error: \(error.localizedDescription)"
            }
            task.waitUntilExit()
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            let text =
                String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "(no output)" : text
        }.value
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
        process = nil

        // Fresh context: new session ID, dropped history.
        conversationID = UUID().uuidString.lowercased()
        messages = []
        awaitingResponse = false
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    func stop() {
        try? stdinHandle?.close()
        stdinHandle = nil
    }

    // Restart keeps messages and conversationID — Banner-Restart + mode-toggle
    // resume both want to land back in the same conversation; only /clear
    // creates a fresh one (see clearAndRestart).
    func restart() {
        guard case .exited = state else { return }
        awaitingResponse = false
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    // Mode-switch path back to chat — wait for the SwiftTerm-side claude to
    // actually exit (signalled via markExternalHandOffDone from the bridge's
    // processTerminated delegate) before spawning chat-claude under the same
    // session-id, otherwise the lock race produces "Session ID … in use".
    func resumeAfterHandOff() {
        awaitingResponse = false
        state = .starting(cwd: cwd)
        guard autoSpawn else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.awaitHandOff()
            guard case .starting = self.state else { return }
            self.spawn()
        }
    }

    // Synchronous tear-down for mode switches: the other pane is about to
    // claim the same session log, so this subprocess must release it before
    // the next spawn — otherwise the two claude processes race the file lock.
    // Synchronous tear-down for mode switches. handOffPending tracks the
    // actual death of the chat subprocess (claude's session-id lock outlives
    // the SIGTERM by some hundreds of ms while it flushes).
    func handOff() {
        guard let dying = process else {
            handOffPending = false
            try? stdinHandle?.close()
            stdinHandle = nil
            readTask?.cancel()
            readTask = nil
            awaitingResponse = false
            state = .exited(code: 0, reason: .userClosed)
            return
        }
        handOffPending = true
        // Replace the original terminationHandler so handleExit doesn't fire
        // (we're shutting down deliberately) and we can observe the death.
        dying.terminationHandler = { _ in
            Task { @MainActor [weak self] in
                self?.handOffPending = false
            }
        }
        dying.terminate()
        try? stdinHandle?.close()
        stdinHandle = nil
        readTask?.cancel()
        readTask = nil
        process = nil
        awaitingResponse = false
        state = .exited(code: 0, reason: .userClosed)
    }

    // External hooks for the terminal-mode subprocess (owned by SwiftTerm,
    // not by ClaudeSession). The bridge calls beginExternalHandOff() in
    // dismantleNSView() and markExternalHandOffDone() in processTerminated.
    func beginExternalHandOff() {
        handOffPending = true
    }

    func markExternalHandOffDone() {
        handOffPending = false
    }

    // Called from the toggle's Binding setter BEFORE modeRaw mutates, so the
    // about-to-mount view's spawn Task sees handOffPending=true and waits.
    func markHandOffStarting() {
        handOffPending = true
    }

    func awaitHandOff(timeout: Duration = .seconds(3)) async {
        guard handOffPending else { return }
        let start = ContinuousClock().now
        while handOffPending {
            try? await Task.sleep(for: .milliseconds(50))
            if ContinuousClock().now - start > timeout { break }
        }
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let encoded = cwd.path.replacingOccurrences(of: "/", with: "-")
        return
            home
            .appendingPathComponent(".claude/projects/\(encoded)")
            .appendingPathComponent("\(conversationID).jsonl")
    }

    // Parse claude's saved session log and replace `messages` with what was
    // exchanged across previous runs (including terminal-mode turns Plumage
    // never observed on its own stdout stream). Called from spawn() so chat
    // mode always reflects the full conversation regardless of which mode it
    // happened in.
    private func rehydrateMessagesFromSessionLog() {
        let file = sessionLogURL()
        guard let data = try? Data(contentsOf: file),
            let raw = String(data: data, encoding: .utf8)
        else { return }

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
            // Drop Plumage- or claude-side <command-…> wrapper payloads;
            // they're not human-visible turns.
            if text.hasPrefix("<") && text.contains("</") { continue }
            hydrated.append(
                ChatMessage(id: UUID(), role: role, text: text, timestamp: .now)
            )
        }
        if !hydrated.isEmpty {
            messages = hydrated
        }
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

    func handleExit(code: Int32) {
        switch state {
        case .idle, .exited:
            return
        case .starting, .running:
            state = .exited(code: code, reason: Self.classify(code))
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
            ] + resumeOrInitArgs()
        newProcess.standardInput = stdinPipe
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = FileHandle.nullDevice

        newProcess.terminationHandler = { terminated in
            let code = terminated.terminationStatus
            Task { @MainActor [weak self] in
                self?.handleExit(code: code)
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
        // terminal-mode subprocess wrote since last time. Safe even on the
        // first spawn (no file → no-op).
        rehydrateMessagesFromSessionLog()
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

        readTask = Task { @MainActor [weak self] in
            for await line in stream {
                guard let self else { return }
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8) else { continue }
                guard
                    let event = try? JSONDecoder().decode(
                        ClaudeStreamEvent.self, from: data)
                else { continue }
                self.handleEvent(event)
            }
        }
    }

    private nonisolated final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var partial: String = ""

        func append(_ data: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            guard let chunk = String(data: data, encoding: .utf8) else { return [] }
            partial += chunk
            var lines: [String] = []
            while let nl = partial.range(of: "\n") {
                lines.append(String(partial[..<nl.lowerBound]))
                partial.removeSubrange(..<nl.upperBound)
            }
            return lines
        }

        func flush() -> String? {
            lock.lock()
            defer { lock.unlock() }
            let remaining = partial
            partial = ""
            return remaining.isEmpty ? nil : remaining
        }
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(
            ChatMessage(id: UUID(), role: .system, text: text, timestamp: .now)
        )
    }

    private func appendAssistant(_ content: AssistantContent) {
        switch content {
        case .text(let text):
            messages.append(
                ChatMessage(id: UUID(), role: .assistant, text: text, timestamp: .now)
            )
        case .toolUse(let name):
            messages.append(
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

    private nonisolated static func classify(_ code: Int32) -> ExitReason {
        switch code {
        case 0: return .userClosed
        case 128...159: return .killed
        default: return .crashed
        }
    }
}
