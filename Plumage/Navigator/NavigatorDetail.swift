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
        case .doc(let relativePath):
            DocEditorView(fileURL: projectURL.appendingPathComponent(relativePath))
        case .claudeMD:
            DocEditorView(fileURL: ClaudeProjectFiles.claudeMDURL(projectURL: projectURL))
        case .hook(let name):
            DocEditorView(
                fileURL:
                    projectURL
                    .appendingPathComponent(ClaudeProjectFiles.hooksRelativePath, isDirectory: true)
                    .appendingPathComponent(name)
            )
        case .skillFile(let skill, let relativePath):
            DocEditorView(
                fileURL:
                    projectURL
                    .appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
                    .appendingPathComponent(skill, isDirectory: true)
                    .appendingPathComponent(relativePath)
            )
        case .settings(let file):
            DocEditorView(fileURL: ClaudeProjectFiles.settingsURL(projectURL: projectURL, file: file))
        }
    }
}
