import Foundation
import Observation

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

    init(storeURL: URL? = nil) {
        let resolvedStore: URL
        if let storeURL {
            resolvedStore = storeURL
        } else {
            resolvedStore =
                (try? ApplicationSupport.recentFileURL())
                ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
                    "Plumage-recent-fallback.json"
                )
        }
        self.storeURL = resolvedStore
        self.items = Self.loadFromDisk(at: resolvedStore)
    }

    func add(url: URL, name: String) {
        var next = items.filter { $0.url != url }
        next.insert(RecentItem(url: url, name: name), at: 0)
        if next.count > Self.maxItems {
            next = Array(next.prefix(Self.maxItems))
        }
        items = next
        persist()
    }

    private func persist() {
        let parent = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private static func loadFromDisk(at url: URL) -> [RecentItem] {
        guard FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([RecentItem].self, from: data)
        else {
            return []
        }
        return decoded
    }
}
