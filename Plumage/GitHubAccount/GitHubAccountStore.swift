import Foundation
import os

nonisolated struct GitHubAccountStore: Sendable {
    private let storeURL: URL

    private static let logger = Logger(subsystem: "com.plumage", category: "GitHubAccountStore")

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    init(fileManager: FileManager = .default) {
        let resolved: URL
        do {
            resolved = try ApplicationSupport.githubAccountsFileURL(using: fileManager)
        } catch {
            Self.logger.error(
                "Application Support unavailable, falling back to tmp: \(error.localizedDescription, privacy: .public)"
            )
            resolved = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("Plumage-github-accounts-fallback.json")
        }
        self.storeURL = resolved
    }

    // A corrupt or missing file degrades to empty rather than throwing: no token
    // rides on load, so an empty list is always a safe fallback.
    func load() -> [GitHubAccount] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storeURL)
            return try Self.decoder.decode([GitHubAccount].self, from: data)
        } catch {
            Self.logger.error(
                "Load failed at \(storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func save(_ accounts: [GitHubAccount]) throws {
        let parent = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(accounts)
        try data.write(to: storeURL, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
