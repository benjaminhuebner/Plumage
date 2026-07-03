import Foundation
import os

nonisolated enum MergeTargetStore {
    static let fileName = "merge-target.json"

    private static let logger = Logger(subsystem: "com.plumage", category: "MergeTargetStore")

    // Envelope object so future fields don't break older readers.
    struct Stored: Codable, Sendable {
        var targetBranch: String
    }

    static func load(bundle: URL) -> String? {
        let url = bundle.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            logger.error("merge-target.json unreadable at \(url.path, privacy: .public)")
            return nil
        }
        do {
            return try JSONDecoder().decode(Stored.self, from: data).targetBranch
        } catch {
            logger.error(
                "merge-target.json corrupt at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    static func save(_ targetBranch: String, bundle: URL) throws {
        let url = bundle.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(Stored(targetBranch: targetBranch))
        try data.write(to: url, options: [.atomic])
    }
}
