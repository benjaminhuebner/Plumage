import Foundation
import os

nonisolated enum NavigatorRoute: Hashable, Sendable, Codable {
    case kanban
    case issue(folderName: String)
    case projectFile(relativePath: String)
    case projectSettings

    func managedFileURL(in projectURL: URL) -> URL? {
        switch self {
        case .projectFile(let rel):
            return projectURL.appendingPathComponent(rel)
        case .kanban, .issue, .projectSettings:
            return nil
        }
    }
}

nonisolated extension NavigatorRoute {
    // nil = unaffected, so the caller keeps the current route; an out-of-scope
    // move or a removal resolves to .kanban.
    static func rewritten(_ route: NavigatorRoute, by rewrites: [RouteRewrite]) -> NavigatorRoute? {
        switch route {
        case .projectFile(let current):
            return rewrittenProjectFile(current, by: rewrites)
        case .issue(let folderName):
            return rewrittenIssue(folderName, by: rewrites)
        case .kanban, .projectSettings:
            return nil
        }
    }

    private static func rewrittenProjectFile(
        _ current: String, by rewrites: [RouteRewrite]
    )
        -> NavigatorRoute?
    {
        for rewrite in rewrites {
            switch rewrite {
            case .moved(let old, let new):
                if current == old { return .projectFile(relativePath: new) }
                if current.hasPrefix(old + "/") {
                    return .projectFile(relativePath: new + String(current.dropFirst(old.count)))
                }
            case .removed(let old):
                if current == old || current.hasPrefix(old + "/") { return .kanban }
            }
        }
        return nil
    }

    private static func rewrittenIssue(
        _ folderName: String, by rewrites: [RouteRewrite]
    )
        -> NavigatorRoute?
    {
        let issuesPrefix = IssueLayout.issuesRelativePrefix
        let issuePath = issuesPrefix + folderName
        for rewrite in rewrites {
            switch rewrite {
            case .moved(let old, let new):
                guard old == issuePath || issuePath.hasPrefix(old + "/") else { continue }
                let renamed =
                    new.hasPrefix(issuesPrefix) ? String(new.dropFirst(issuesPrefix.count)) : ""
                if old == issuePath, !renamed.isEmpty, !renamed.contains("/") {
                    return .issue(folderName: renamed)
                }
                // Moved out of the issues directory (or an ancestor moved): the
                // route can't follow.
                return .kanban
            case .removed(let old):
                if old == issuePath || issuePath.hasPrefix(old + "/") { return .kanban }
            }
        }
        return nil
    }
}

nonisolated extension NavigatorRoute {
    // JSONEncoder/Decoder are Sendable; caching saves a per-call allocation
    // on the SceneStorage persist hot path.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    var persistedString: String {
        guard
            let data = try? Self.encoder.encode(self),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    // Decodes a SceneStorage-persisted route. Tries to migrate legacy JSON
    // shapes first so existing windows reopen without a fallback to `.kanban`.
    // Anything unrecognised returns nil; callers default to `.kanban`.
    init?(persistedString: String) {
        guard
            !persistedString.isEmpty,
            let data = persistedString.data(using: .utf8)
        else {
            return nil
        }
        if let migrated = Self.migrateLegacyJSON(data: data) {
            self = migrated
            return
        }
        do {
            self = try Self.decoder.decode(NavigatorRoute.self, from: data)
        } catch {
            // nil falls back to .kanban at the caller — log so a persisted
            // route silently degrading to the board is diagnosable.
            Logger(subsystem: "com.plumage", category: "NavigatorRoute").error(
                "persisted route undecodable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // Maps legacy route JSON tags to `.projectFile`. The shape
    // of each tag mirrors what Swift's auto-Codable wrote for that case.
    fileprivate static func migrateLegacyJSON(data: Data) -> NavigatorRoute? {
        guard
            let object =
                (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        if let payload = object["managedFile"] as? [String: Any],
            let typeRaw = payload["type"] as? String,
            let rel = payload["relativePath"] as? String
        {
            return .projectFile(
                relativePath: "\(managedFileBase(typeRaw))/\(rel)")
        }
        if object["claudeMD"] != nil {
            return .projectFile(relativePath: ".claude/CLAUDE.md")
        }
        if object["claudeLocalMD"] != nil {
            return .projectFile(relativePath: ".claude/CLAUDE.local.md")
        }
        if let payload = object["claudeMarkdown"] as? [String: Any],
            let name = payload["name"] as? String
        {
            return .projectFile(relativePath: ".claude/\(name)")
        }
        if object["mcpJSON"] != nil {
            return .projectFile(relativePath: ".mcp.json")
        }
        if let payload = object["skillFile"] as? [String: Any],
            let skill = payload["skill"] as? String,
            let rel = payload["relativePath"] as? String
        {
            return .projectFile(relativePath: ".claude/skills/\(skill)/\(rel)")
        }
        if let payload = object["settings"] as? [String: Any],
            let raw = payload["_0"] as? String
        {
            return .projectFile(relativePath: ".claude/\(raw)")
        }
        return nil
    }

    private static func managedFileBase(_ typeRaw: String) -> String {
        switch typeRaw {
        case "docs": return ".claude/docs"
        case "hooks": return ".claude/hooks"
        case "agents": return ".claude/agents"
        case "rules": return ".claude/rules"
        case "outputStyles": return ".claude/output-styles"
        default: return ".claude"
        }
    }
}
