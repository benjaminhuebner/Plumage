import Foundation
import Observation

@Observable
@MainActor
final class TerminalClaudeSession {
    enum State: Sendable, Equatable {
        case idle
        case starting(cwd: URL)
        case running
        case exited(code: Int32, reason: ClaudeSession.ExitReason)
    }

    let cwd: URL
    let binaryURL: URL
    private let sessionIDStoreURL: URL
    private let sessionLogRoot: URL

    private(set) var state: State = .idle
    private(set) var conversationID: String

    init(
        cwd: URL,
        binaryURL: URL,
        sessionIDStoreOverride: URL? = nil,
        sessionLogRoot: URL? = nil
    ) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.sessionIDStoreURL =
            sessionIDStoreOverride
            ?? cwd
            .appendingPathComponent(".plumage", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("terminal-id")
        self.sessionLogRoot =
            sessionLogRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        if let persisted = Self.loadPersistedID(from: self.sessionIDStoreURL) {
            self.conversationID = persisted
        } else {
            let fresh = UUID().uuidString.lowercased()
            self.conversationID = fresh
            Self.persistID(fresh, to: self.sessionIDStoreURL)
        }
    }

    static func rebuilt(
        for handleURL: URL, replacing prior: TerminalClaudeSession
    ) -> TerminalClaudeSession {
        if prior.cwd == handleURL { return prior }
        prior.stop()
        let binary =
            (try? ProductionProcessRunner.locateBinary())
            ?? URL(filePath: "/dev/null")
        return TerminalClaudeSession(cwd: handleURL, binaryURL: binary)
    }

    func attach() {
        switch state {
        case .idle, .exited:
            state = .starting(cwd: cwd)
        case .starting, .running:
            break
        }
    }

    func markStarted() {
        if case .starting = state {
            state = .running
        }
    }

    func markExited(code: Int32) {
        switch state {
        case .idle, .exited:
            return
        case .starting, .running:
            state = .exited(code: code, reason: Self.classify(code))
        }
    }

    func stop() {
        switch state {
        case .starting, .running:
            state = .exited(code: 0, reason: .userClosed)
        case .idle, .exited:
            return
        }
    }

    func resumeOrInitArgs() -> [String] {
        guard sessionLogExists() else {
            return ["--session-id", conversationID]
        }
        return ["--resume", conversationID]
    }

    // /bin/sh -c "cd '<cwd>' && exec '<claude>' [--session-id|--resume '<uuid>']"
    func shellSpawnArgs() -> [String] {
        let quotedCwd = cwd.path.replacingOccurrences(of: "'", with: #"'\''"#)
        let quotedBin = binaryURL.path.replacingOccurrences(of: "'", with: #"'\''"#)
        let attach = Self.shellQuotedAttachArgs(resumeOrInitArgs())
        return ["-c", "cd '\(quotedCwd)' && exec '\(quotedBin)' \(attach)"]
    }

    static func shellQuotedAttachArgs(_ args: [String]) -> String {
        args.map { arg in
            precondition(isShellSafe(arg), "shellQuotedAttachArgs: unsafe arg")
            let escaped = arg.replacingOccurrences(of: "'", with: #"'\''"#)
            return "'\(escaped)'"
        }
        .joined(separator: " ")
    }

    static func isShellSafe(_ value: String) -> Bool {
        !value.contains("\0") && !value.contains("\n") && !value.contains("\r")
    }

    private func sessionLogExists() -> Bool {
        FileManager.default.fileExists(atPath: sessionLogURL().path)
    }

    private func sessionLogURL() -> URL {
        let encoded = cwd.path.replacingOccurrences(of: "/", with: "-")
        return
            sessionLogRoot
            .appendingPathComponent(encoded)
            .appendingPathComponent("\(conversationID).jsonl")
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

    private nonisolated static func classify(_ code: Int32) -> ClaudeSession.ExitReason {
        switch code {
        case 0: return .userClosed
        case 128...159: return .killed
        default: return .crashed
        }
    }
}
