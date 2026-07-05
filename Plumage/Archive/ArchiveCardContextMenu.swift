import AppKit
import SwiftUI

struct ArchiveCardContextMenu: View {
    let folderName: String
    let folderURL: URL
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.openSpec) private var openSpec

    var body: some View {
        Button("Unarchive") {
            kanban.applyOptimisticUnarchive(folderName: folderName, projectURL: projectURL)
        }
        Button("Open") {
            openSpec(.archivedIssue(folderName: folderName))
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        }
        Button("Move to Trash", role: .destructive) {
            kanban.requestArchiveTrash(folderName: folderName)
        }
    }
}
