import Foundation
import os

// Project-scoped, ordered set of pinned project-relative file paths backing
// the sidebar's "Pinned" section. Mutations land in-memory on the MainActor
// and persist off-Main via `PinnedFilesStore` (atomic write). Mirrors
// NavigatorModel's @MainActor @Observable + Task.detached I/O pattern.
@MainActor
@Observable
final class PinnedFilesModel {
    private(set) var pinned: [String] = []

    // Captured on loadOrSeed so `apply(rewrites:)` — whose call site (the
    // routeRewrites observer) has no projectURL to pass — can still persist a
    // followed rename. Always set before any rewrite can arrive.
    private var projectURL: URL?
    private var pendingPersist: Task<Void, Never>?

    private nonisolated static let log = Logger(subsystem: "com.plumage", category: "PinnedFiles")

    isolated deinit {
        pendingPersist?.cancel()
    }

    func contains(_ relativePath: String) -> Bool {
        pinned.contains(relativePath)
    }

    // Loads the persisted pin set, or seeds defaults when pins.json is absent.
    // A present-but-empty file (user unpinned everything, or a corrupt file)
    // is honoured as-is and never reseeded.
    func loadOrSeed(projectURL: URL) async {
        self.projectURL = projectURL
        let result = await Task.detached(priority: .userInitiated) { () -> [String] in
            guard let bundle = try? BundleResolver.resolve(from: projectURL).bundle else {
                Self.log.error(
                    "loadOrSeed: no bundle for \(projectURL.path, privacy: .public)")
                return []
            }
            if let loaded = PinnedFilesStore.load(bundle: bundle) {
                Self.log.info(
                    "loadOrSeed: loaded \(loaded.count) pin(s) from existing pins.json")
                return loaded
            }
            let seeded = PinnedFilesStore.seedDefaults(projectURL: projectURL)
            Self.log.info(
                "loadOrSeed: no pins.json, seeded \(seeded.count) default(s): \(seeded, privacy: .public)")
            do {
                try PinnedFilesStore.save(seeded, bundle: bundle)
            } catch {
                Self.log.error("seed persist failed: \(error.localizedDescription, privacy: .public)")
            }
            return seeded
        }.value
        pinned = result
    }

    func toggle(relativePath: String, projectURL: URL) {
        if pinned.contains(relativePath) {
            unpin(relativePath: relativePath, projectURL: projectURL)
        } else {
            pin(relativePath: relativePath, projectURL: projectURL)
        }
    }

    func pin(relativePath: String, projectURL: URL) {
        guard !pinned.contains(relativePath) else { return }
        pinned.append(relativePath)
        persist(pinned, projectURL: projectURL)
    }

    func unpin(relativePath: String, projectURL: URL) {
        guard pinned.contains(relativePath) else { return }
        pinned.removeAll { $0 == relativePath }
        persist(pinned, projectURL: projectURL)
    }

    // Follows in-app rename/move/trash. Moved paths (exact or under a moved
    // folder) are re-pointed; removed paths (exact or descendant) are dropped.
    func apply(rewrites: [RouteRewrite]) {
        var changed = false
        for rewrite in rewrites {
            switch rewrite {
            case .moved(let old, let new):
                for index in pinned.indices {
                    if pinned[index] == old {
                        pinned[index] = new
                        changed = true
                    } else if pinned[index].hasPrefix(old + "/") {
                        pinned[index] = new + String(pinned[index].dropFirst(old.count))
                        changed = true
                    }
                }
            case .removed(let old):
                let before = pinned.count
                pinned.removeAll { $0 == old || $0.hasPrefix(old + "/") }
                if pinned.count != before { changed = true }
            }
        }
        if changed, let projectURL {
            persist(pinned, projectURL: projectURL)
        }
    }

    private func persist(_ paths: [String], projectURL: URL) {
        // Chained off the prior write (RecentProjects discipline): independent
        // fire-and-forget tasks can land on disk out of order, persisting a
        // stale pin set over a newer one.
        let prior = pendingPersist
        pendingPersist = Task.detached(priority: .utility) {
            await prior?.value
            guard let bundle = try? BundleResolver.resolve(from: projectURL).bundle else {
                Self.log.error("persist skipped: no bundle for \(projectURL.path, privacy: .public)")
                return
            }
            do {
                try PinnedFilesStore.save(paths, bundle: bundle)
            } catch {
                Self.log.error("persist failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
