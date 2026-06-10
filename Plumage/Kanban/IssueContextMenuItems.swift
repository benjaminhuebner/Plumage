import AppKit
import SwiftUI

struct IssueContextMenuItems: View {
    let folderName: String
    let folderURL: URL
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban

    var body: some View {
        Group {
            // Both route through a confirmation dialog (ProjectWindow) — the
            // card disappears instantly and archive has no restore UI.
            Button("Archive") {
                kanban.requestArchive(folderName: folderName)
            }
            Button("Move to Trash", role: .destructive) {
                kanban.requestTrash(folderName: folderName)
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            }
        }
    }
}
