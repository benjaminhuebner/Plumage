import Foundation
import os

nonisolated enum SidebarExpansionStore {
    static let fileName = "sidebar-expansion.json"

    private static let logger = Logger(
        subsystem: "com.plumage", category: "SidebarExpansionStore")

    // Small forward-compatible envelope. A future field can be added without
    // breaking older readers (unknown keys are ignored by JSONDecoder).
    struct Stored: Codable, Sendable {
        var expanded: [String]
    }

    static func load(projectURL: URL) -> Set<String> {
        guard let bundle = try? BundleResolver.resolve(from: projectURL).bundle else { return [] }
        let url = bundle.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return Set(try JSONDecoder().decode(Stored.self, from: data).expanded)
        } catch {
            logger.error(
                "\(fileName) corrupt at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }

    static func save(_ paths: Set<String>, projectURL: URL) {
        guard let bundle = try? BundleResolver.resolve(from: projectURL).bundle else {
            logger.error("save skipped: no bundle for \(projectURL.path, privacy: .public)")
            return
        }
        let url = bundle.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(Stored(expanded: paths.sorted()))
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
