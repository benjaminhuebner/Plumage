import Foundation

nonisolated enum NavigatorRoute: Hashable, Sendable, Codable {
    case kanban
    case issue(folderName: String)
    case doc(relativePath: String)
    case claudeMD
    case hook(name: String)
    case skillFile(skill: String, relativePath: String)
    case settings(SettingsFile)
}

nonisolated enum SettingsFile: String, Hashable, Sendable, Codable, CaseIterable {
    case main = "settings.json"
    case local = "settings.local.json"
}

nonisolated extension NavigatorRoute {
    // String form used by @SceneStorage to persist sidebar selection per
    // window. JSON-encoded so all associated values survive round-trip
    // without a hand-rolled tag/payload format.
    var persistedString: String {
        guard
            let data = try? JSONEncoder().encode(self),
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
            let decoded = try? JSONDecoder().decode(NavigatorRoute.self, from: data)
        else {
            return nil
        }
        self = decoded
    }
}
