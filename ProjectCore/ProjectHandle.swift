import Foundation

nonisolated struct ProjectHandle: Hashable, Codable, Sendable {
    let url: URL
}
