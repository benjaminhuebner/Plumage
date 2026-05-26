import Foundation

nonisolated enum NavigatorRoute: Hashable, Sendable, Codable {
    case kanban
    case issue(folderName: String)
    case managedFile(type: ManagedFileType, relativePath: String)
    case claudeMD
    case claudeLocalMD
    case claudeMarkdown(name: String)
    case mcpJSON
    case skillFile(skill: String, relativePath: String)
    case settings(SettingsFile)
    // Per-project Plumage settings (workflow command overrides, model picks
    // for Chat / Terminals / Workflow tabs). Detail-view is a custom
    // ProjectSettingsView, not a JSON file editor.
    case projectSettings

    // On-disk URL for routes that point at a user-managed file (rename, trash,
    // open in DocEditor). Returns nil for routes that don't map to a single
    // managed file (`.kanban`, `.issue`, bootstrap files / settings).
    func managedFileURL(in projectURL: URL) -> URL? {
        switch self {
        case .managedFile(let type, let rel):
            return
                projectURL
                .appendingPathComponent(type.relativePath, isDirectory: true)
                .appendingPathComponent(rel)
        case .claudeMarkdown(let name):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.settingsRootRelativePath, isDirectory: true)
                .appendingPathComponent(name)
        case .skillFile(let skill, let path):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
                .appendingPathComponent(skill, isDirectory: true)
                .appendingPathComponent(path)
        case .kanban, .issue, .claudeMD, .claudeLocalMD, .mcpJSON, .settings,
            .projectSettings:
            return nil
        }
    }
}

nonisolated enum SettingsFile: String, Hashable, Sendable, Codable, CaseIterable {
    case main = "settings.json"
    case local = "settings.local.json"
}

nonisolated extension NavigatorRoute {
    // JSONEncoder/Decoder are Sendable; caching saves a per-call allocation
    // on the SceneStorage persist hot path (every selectedRoute change
    // re-encodes).
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // String form used by @SceneStorage to persist sidebar selection per
    // window. JSON-encoded so all associated values survive round-trip
    // without a hand-rolled tag/payload format. Decode failures (e.g. an
    // old window persisted `.doc(relativePath:)` before this issue removed
    // the case) fall through to nil; callers default to `.kanban`.
    var persistedString: String {
        guard
            let data = try? Self.encoder.encode(self),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    init?(persistedString: String) {
        guard
            !persistedString.isEmpty,
            let data = persistedString.data(using: .utf8),
            let decoded = try? Self.decoder.decode(NavigatorRoute.self, from: data)
        else {
            return nil
        }
        self = decoded
    }
}
