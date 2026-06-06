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
    private var pendingPersist: Task<Void, Never>?

    nonisolated private static let logger = Logger(
        subsystem: "com.plumage",
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

    // Updates the cached display name of the recent matching `url`. A project
    // rename keeps the root URL (the key) but changes the name; this refreshes
    // the Welcome list without reordering. No-op when the project isn't listed
    // or the name is unchanged.
    //
    // Reconciles the persisted file, not just the in-memory list: at launch the
    // in-memory `items` can be clobbered back to the on-disk state by a load()
    // that races add()'s async persist, so a window may hold an empty/stale
    // `items` by the time a rename fires. Treating the store as source of truth
    // — read-modify-write through the persist chain — makes the rename land
    // regardless. The in-memory list is updated too so a visible Welcome stays
    // live.
    //
    // Matches on the symlink-resolved path, not raw URL equality: the open path
    // stores the URL as delivered by LaunchServices (often the symlink-resolved
    // form, e.g. /private/tmp/…) while a caller may pass the unresolved root
    // (/tmp/…). Comparing resolved paths makes the lookup robust to that.
    func update(url: URL, name: String) {
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        if let index = items.firstIndex(where: {
            $0.url.resolvingSymlinksInPath().standardizedFileURL.path == target
        }), items[index].name != name {
            items[index] = RecentItem(url: items[index].url, name: name)
        }
        // Chain off pendingPersist so this read-modify-write can't race a
        // concurrent add()/persist on the same store.
        let store = storeURL
        let prior = pendingPersist
        pendingPersist = Task.detached(priority: .utility) {
            _ = await prior?.value
            var stored = Self.loadFromDisk(at: store)
            guard
                let idx = stored.firstIndex(where: {
                    $0.url.resolvingSymlinksInPath().standardizedFileURL.path == target
                }),
                stored[idx].name != name
            else { return }
            stored[idx] = RecentItem(url: stored[idx].url, name: name)
            Self.persistToDisk(items: stored, at: store)
        }
    }

    private func persist() {
        let snapshot = items
        let url = storeURL
        let prior = pendingPersist
        pendingPersist = Task.detached(priority: .utility) {
            // Chain so two quick add() calls write in order — otherwise a
            // late-scheduled older snapshot could overwrite the newer one.
            _ = await prior?.value
            Self.persistToDisk(items: snapshot, at: url)
        }
    }

    // Test hook so round-trip tests can deterministically wait for the
    // detached write before re-reading the file.
    func flushPendingWrites() async {
        await pendingPersist?.value
    }

    nonisolated private static func persistToDisk(items: [RecentItem], at storeURL: URL) {
        do {
            let parent = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            logger.error(
                "Persist failed at \(storeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
