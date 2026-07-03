import Foundation

// No secrets here — the token lives in the keychain, never in this metadata.
nonisolated struct GitHubAccount: Codable, Identifiable, Hashable, Sendable {
    static let defaultHost = "github.com"

    let login: String
    let host: String
    var name: String?
    var avatarURL: URL?
    var scopes: [String]
    let addedAt: Date

    var id: String { Self.identifier(login: login, host: host) }

    // Format doubles as the keychain account key — keep it stable.
    static func identifier(login: String, host: String) -> String {
        "\(login)@\(host)"
    }
}
