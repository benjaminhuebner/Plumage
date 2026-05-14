import Foundation

nonisolated enum SpecRoute: Hashable, Codable, Sendable {
    case spec(folderName: String)
    case rawEditor(folderName: String)
}
