import Foundation

// Scene-scoped hand-off for the chosen folder. The command picks a folder and
// sets `folderURL` before opening the single-instance Migrate window, which
// reads it back. Injected app-wide via `.environment`, mirroring how
// `RecentProjects` reaches every scene.
@Observable
@MainActor
final class MigrationRequest {
    private(set) var folderURL: URL?

    // Bumped on every present so the single-instance Migrate window rebuilds its
    // model even when re-requested for the *same* folder — otherwise a `.task(id:
    // folderURL)` wouldn't re-fire and a stale completion screen would show.
    private(set) var generation = 0

    func present(_ url: URL) {
        folderURL = url
        generation += 1
    }
}
