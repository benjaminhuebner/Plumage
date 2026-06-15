import Foundation

// `cwd`/`sessionID` key each payload line back to a live run.
nonisolated struct AgentNotificationSignal: Codable, Equatable, Sendable {
    let sessionID: String
    let cwd: String
    let notificationType: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case cwd
        case notificationType = "notification_type"
        case message
    }

    static func parse(line: String, decoder: JSONDecoder = JSONDecoder()) -> AgentNotificationSignal? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? decoder.decode(AgentNotificationSignal.self, from: data)
    }
}

// Injects a launch-scoped claude `Notification` hook via --settings (verified to
// merge with, not clobber, the project's committed hooks) so a blocked/idle run
// signals attention with zero footprint in the project tree.
nonisolated enum AgentNotificationHook {
    static func appSupportDirectory(fileManager: FileManager = .default) -> URL {
        let base =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Plumage", isDirectory: true)
    }

    // One shared file every implement run appends to; the app coordinator watches
    // it and maps each line to a run by cwd. App-support, not the project tree.
    static func signalFileURL(fileManager: FileManager = .default) -> URL {
        appSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("agent-notifications.jsonl")
    }

    // The path is POSIX-quoted so the space in "Application Support" survives;
    // the outer --settings quoting then escapes those quotes in turn.
    static func appendCommand(signalFileURL: URL) -> String {
        "{ cat; echo; } >> \(TerminalClaudeSession.shellQuote(signalFileURL.path))"
    }

    // nil if the result wouldn't be shell-safe, so the caller falls back to
    // theme-only rather than emit an injectable string.
    static func settingsJSON(dark: Bool, signalFileURL: URL) -> String? {
        let theme =
            dark
            ? ClaudeThemeInstaller.settingsThemeValue : ClaudeThemeInstaller.lightSettingsThemeValue
        let settings: [String: Any] = [
            "theme": theme,
            "promptSuggestionEnabled": false,
            "hooks": [
                "Notification": [
                    ["hooks": [["type": "command", "command": appendCommand(signalFileURL: signalFileURL)]]]
                ]
            ],
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]),
            let json = String(data: data, encoding: .utf8),
            TerminalClaudeSession.isShellSafe(json)
        else { return nil }
        return json
    }

    // One run per checkout, so cwd alone is unambiguous and parallel-safe.
    static func liveRun(
        for signal: AgentNotificationSignal, among runs: [WorktreeImplementRun]
    ) -> WorktreeImplementRun? {
        let signalRoot = Self.canonicalPath(URL(filePath: signal.cwd))
        return runs.first { Self.canonicalPath($0.checkoutRoot) == signalRoot }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
