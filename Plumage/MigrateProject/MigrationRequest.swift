import Foundation

// Scene-scoped hand-off for the chosen folder. The command picks a folder and
// sets `folderURL` before opening the single-instance Migrate window, which
// reads it back. Injected app-wide via `.environment`, mirroring how
// `RecentProjects` reaches every scene (#00060).
@Observable
@MainActor
final class MigrationRequest {
    var folderURL: URL?
}
