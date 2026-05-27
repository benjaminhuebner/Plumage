import Foundation

nonisolated enum NavigatorRoute: Hashable, Sendable, Codable {
    case kanban
    case issue(folderName: String)
    case projectFile(relativePath: String)
    case projectSettings

    // Legacy file-route cases — kept temporarily so existing call-sites
    // compile while the rewrite proceeds. New code constructs
    // `.projectFile(relativePath:)`. The `persistedString` decoder migrates
    // any legacy shape to `.projectFile`, so SceneStorage data written by
    // older builds is auto-upgraded on first launch.
    case managedFile(type: ManagedFileType, relativePath: String)
    case claudeMD
    case claudeLocalMD
    case claudeMarkdown(name: String)
    case mcpJSON
    case skillFile(skill: String, relativePath: String)
    case settings(SettingsFile)

    func managedFileURL(in projectURL: URL) -> URL? {
        switch self {
        case .projectFile(let rel):
            return projectURL.appendingPathComponent(rel)
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

    // Maps a legacy file-route case to its `.projectFile` equivalent. Returns
    // `nil` for routes that need no migration. The mapping mirrors
    // `managedFileURL(in:)`'s on-disk path so persisted SceneStorage values
    // and live runtime URLs stay consistent.
    fileprivate func migratedToProjectFile() -> NavigatorRoute? {
        switch self {
        case .managedFile(let type, let rel):
            return .projectFile(relativePath: "\(type.relativePath)/\(rel)")
        case .claudeMD:
            return .projectFile(relativePath: ClaudeProjectFiles.claudeMDRelativePath)
        case .claudeLocalMD:
            return .projectFile(relativePath: ClaudeProjectFiles.claudeLocalMDRelativePath)
        case .claudeMarkdown(let name):
            return .projectFile(
                relativePath: "\(ClaudeProjectFiles.settingsRootRelativePath)/\(name)")
        case .mcpJSON:
            return .projectFile(relativePath: ClaudeProjectFiles.mcpJSONRelativePath)
        case .skillFile(let skill, let rel):
            return .projectFile(
                relativePath: "\(ClaudeProjectFiles.skillsRelativePath)/\(skill)/\(rel)")
        case .settings(let file):
            return .projectFile(
                relativePath: "\(ClaudeProjectFiles.settingsRootRelativePath)/\(file.rawValue)")
        case .kanban, .issue, .projectFile, .projectSettings:
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
    // without a hand-rolled tag/payload format. Decode failures fall
    // through to nil; callers default to `.kanban`.
    var persistedString: String {
        guard
            let data = try? Self.encoder.encode(self),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    // Migrates any legacy file-case shape to `.projectFile` so SceneStorage
    // data written by builds that predate the route collapse is upgraded on
    // decode. Anything that doesn't match a known shape (corrupt JSON, an
    // enum case removed entirely in an even-earlier refactor) returns nil
    // and the caller defaults to `.kanban`.
    init?(persistedString: String) {
        guard
            !persistedString.isEmpty,
            let data = persistedString.data(using: .utf8),
            let decoded = try? Self.decoder.decode(NavigatorRoute.self, from: data)
        else {
            return nil
        }
        self = decoded.migratedToProjectFile() ?? decoded
    }
}
