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

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?

    init(cwd: URL, binaryURL: URL, autoSpawn: Bool = true) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.autoSpawn = autoSpawn
    }

    func start() {
        guard case .idle = state else { return }
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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

    func stop() {
        try? stdinHandle?.close()
        stdinHandle = nil
    }

    func restart() {
        guard case .exited = state else { return }
        messages = []
        awaitingResponse = false
        state = .starting(cwd: cwd)
        if autoSpawn { spawn() }
    }

    func handleEvent(_ event: ClaudeStreamEvent) {
        switch event {
        case .systemInit(let sessionID):
            if case .starting = state {
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
        newProcess.arguments = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
        ]
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

        let stdoutHandle = stdoutPipe.fileHandleForReading
        readTask = Task { @MainActor [weak self] in
            do {
                for try await line in stdoutHandle.bytes.lines {
                    guard let self else { return }
                    guard !line.isEmpty else { continue }
                    guard let data = line.data(using: .utf8) else { continue }
                    guard
                        let event = try? JSONDecoder().decode(
                            ClaudeStreamEvent.self, from: data)
                    else { continue }
                    self.handleEvent(event)
                }
            } catch {
                // stdout read ended — terminationHandler will drive state.
            }
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
