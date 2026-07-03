import Foundation

// Session-log parsing behind rehydrateMessagesFromSessionLog: pure decode
// helpers over claude's on-disk .jsonl, kept apart from the process lifecycle.
extension ClaudeSession {
    nonisolated static let defaultRehydrationCap = 200

    func sessionLogURL() -> URL {
        ClaudeSessionStorage.sessionLogURL(
            root: sessionLogRoot, cwd: cwd, conversationID: conversationID)
    }

    // Explicit list, not a generic "<" heuristic — a real user message may
    // start with markup and must survive rehydration.
    nonisolated private static let machineWrapperPrefixes = [
        "<command-", "<local-command-",
        "<bash-input>", "<bash-stdout>", "<bash-stderr>",
        "<system-reminder>",
    ]

    nonisolated static func parseSessionLog(at file: URL, cap: Int) -> [ChatMessage] {
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
                ChatMessage(id: UUID(), role: role, text: text)
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
}
