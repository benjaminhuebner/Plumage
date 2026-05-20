import AppKit
import SwiftUI

struct IssueContextMenuItems: View {
    let folderName: String
    let folderURL: URL
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban

    var body: some View {
        Group {
            Button("Archive") {
                kanban.applyOptimisticArchive(folderName: folderName, projectURL: projectURL)
            }
            Button("Move to Trash") {
                kanban.applyOptimisticTrash(folderName: folderName, projectURL: projectURL)
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            }
        }
    }
}
