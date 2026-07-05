import SwiftUI

struct NavigatorDetail: View {
    let route: NavigatorRoute
    let projectURL: URL
    let padding: Int

    @Environment(ProjectKanbanModel.self) private var kanban

    var body: some View {
        switch route {
        case .kanban:
            KanbanView(
                grouped: kanban.groupedIssues,
                padding: padding,
                projectURL: projectURL
            )
        case .issue(let folderName):
            IssueDetailView(projectURL: projectURL, folderName: folderName)
        case .archive:
            ArchiveView(projectURL: projectURL, padding: padding)
        case .archivedIssue(let folderName):
            ArchivedIssueReadOnlyView(projectURL: projectURL, folderName: folderName)
        case .projectFile(let relativePath):
            let fileURL = projectURL.appendingPathComponent(relativePath)
            switch NavigatorDetailDispatch.detailViewKind(for: relativePath) {
            case .doc:
                DocEditorView(fileURL: fileURL)
            case .info:
                FileInfoView(fileURL: fileURL)
            case .image:
                ImagePreviewView(fileURL: fileURL)
            }
        case .projectSettings:
            ProjectSettingsView(projectURL: projectURL)
        }
    }
}
