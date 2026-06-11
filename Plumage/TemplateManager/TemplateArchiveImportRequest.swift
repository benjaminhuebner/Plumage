import Foundation

// App-level hand-off for an archive opened from outside the Template Manager
// (Finder double-click). Mirrors MigrationRequest: the app scene sets the URL
// and opens the single-instance window, which reads it back via `.task(id:)`.
@Observable
@MainActor
final class TemplateArchiveImportRequest {
    private(set) var archiveURL: URL?

    // Bumped on every present so re-opening the *same* archive re-fires the
    // window's `.task(id:)` and re-presents the sheet.
    private(set) var generation = 0

    func present(_ url: URL) {
        archiveURL = url
        generation += 1
    }
}
