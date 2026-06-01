import AppKit
import SwiftUI

@MainActor
enum MigrateProjectCommand {
    // Pick an existing folder, then open the Migrate window for it. Welcome is
    // only dismissed once a folder is chosen, so cancelling the panel leaves it
    // up.
    static func presentPicker(
        request: MigrationRequest,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        guard let url = pickFolder() else { return }
        present(for: url, request: request, openWindow: openWindow, dismissWindow: dismissWindow)
    }

    // Open the Migrate window for an already-known folder — e.g. the open path's
    // "this isn't a Plumage project, migrate it?" offer.
    static func present(
        for url: URL,
        request: MigrationRequest,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        request.present(url)
        openWindow(id: "migrate-project")
        dismissWindow(id: "welcome")
    }

    private static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Migrate Existing Project"
        panel.message = "Choose an existing folder to turn into a Plumage project."
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
