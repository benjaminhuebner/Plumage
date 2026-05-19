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
