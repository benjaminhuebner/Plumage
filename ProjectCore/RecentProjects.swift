import Foundation
import Observation
import os

struct RecentItem: Codable, Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    var id: URL { url }
}

@Observable
@MainActor
final class RecentProjects {
    static let maxItems = 50

    private(set) var items: [RecentItem]
    private let storeURL: URL

    nonisolated private static let logger = Logger(
        subsystem: "dev.plumage",
        category: "RecentProjects"
    )

    init(storeURL: URL? = nil) {
        let resolvedStore: URL
        if let storeURL {
            resolvedStore = storeURL
        } else {
            do {
                resolvedStore = try ApplicationSupport.recentFileURL()
            } catch {
                Self.logger.error(
                    "Application Support unavailable, falling back to tmp: \(error.localizedDescription, privacy: .public)"
                )
                resolvedStore = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("Plumage-recent-fallback.json")
            }
        }
        self.storeURL = resolvedStore
        self.items = []
    }

    func load() async {
        let url = storeURL
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadFromDisk(at: url)
        }.value
        items = loaded
    }

    func add(url: URL, name: String) {
        let canonical = url.standardizedFileURL
        var next = items.filter { $0.url != canonical }
        next.insert(RecentItem(url: canonical, name: name), at: 0)
        if next.count > Self.maxItems {
            next = Array(next.prefix(Self.maxItems))
        }
        items = next
        persist()
    }

    private func persist() {
        do {
            let parent = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            Self.logger.error(
                "Persist failed at \(self.storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    nonisolated private static func loadFromDisk(at url: URL) -> [RecentItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([RecentItem].self, from: data)
        } catch {
            logger.error(
                "Load failed at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
