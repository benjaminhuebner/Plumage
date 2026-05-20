import Foundation

nonisolated enum NavigatorRoute: Hashable, Sendable, Codable {
    case kanban
    case issue(folderName: String)
    case doc(relativePath: String)
    case claudeMD
    case claudeMarkdown(name: String)
    case hook(name: String)
    case skillFile(skill: String, relativePath: String)
    case settings(SettingsFile)

    // On-disk URL for routes that point at a user-managed file (rename, trash,
    // open in DocEditor). Returns nil for routes that don't map to a single
    // managed file (`.kanban`, `.issue`, `.claudeMD` bootstrap, `.settings`).
    func managedFileURL(in projectURL: URL) -> URL? {
        switch self {
        case .doc(let rel):
            return projectURL.appendingPathComponent(rel)
        case .claudeMarkdown(let name):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.settingsRootRelativePath, isDirectory: true)
                .appendingPathComponent(name)
        case .hook(let name):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.hooksRelativePath, isDirectory: true)
                .appendingPathComponent(name)
        case .skillFile(let skill, let path):
            return
                projectURL
                .appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
                .appendingPathComponent(skill, isDirectory: true)
                .appendingPathComponent(path)
        case .kanban, .issue, .claudeMD, .settings:
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
    // without a hand-rolled tag/payload format.
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
