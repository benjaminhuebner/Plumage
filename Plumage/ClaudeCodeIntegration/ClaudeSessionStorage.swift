import Foundation

// Shared on-disk conventions for ClaudeSession and TerminalClaudeSession:
// both resolve the same claude session logs and persist conversation IDs
// with identical semantics, so the encoding lives exactly once.
nonisolated enum ClaudeSessionStorage {
    // `/` → `-` mirrors claude CLI's session-log encoding so Plumage finds the
    // same .jsonl claude writes. Paths with `-` could collide post-encoding, but
    // matching claude is the contract — keep in sync if its scheme changes.
    static func sessionLogDirectory(root: URL, cwd: URL) -> URL {
        root.appendingPathComponent(cwd.path.replacingOccurrences(of: "/", with: "-"))
    }

    static func sessionLogURL(root: URL, cwd: URL, conversationID: String) -> URL {
        sessionLogDirectory(root: root, cwd: cwd)
            .appendingPathComponent("\(conversationID).jsonl")
    }

    // --session-id when the session file doesn't exist yet, --resume otherwise.
    // claude's --session-id is strictly "create new" (rejects with "Session ID …
    // already in use" if the .jsonl exists), so we can't pass it on every spawn.
    static func resumeOrInitArgs(conversationID: String, logRoot: URL, cwd: URL) -> [String] {
        let log = sessionLogURL(root: logRoot, cwd: cwd, conversationID: conversationID)
        guard FileManager.default.fileExists(atPath: log.path) else {
            return ["--session-id", conversationID]
        }
        return ["--resume", conversationID]
    }

    static func loadPersistedID(from url: URL?) -> String? {
        guard let url,
            let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return raw
    }

    static func persistID(_ id: String, to url: URL?) {
        guard let url else { return }
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        try? id.write(to: url, atomically: true, encoding: .utf8)
    }
}
