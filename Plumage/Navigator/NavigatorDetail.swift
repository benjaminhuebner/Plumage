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
        case .projectFile(let relativePath):
            // Temporary catch-all: every `.projectFile` opens in DocEditor
            // for now. Task 7 replaces this with a suffix-driven switch
            // (DocEditor for .md/json, FileInfoView for code, ImagePreview
            // for images, FileInfoView for binaries).
            DocEditorView(fileURL: projectURL.appendingPathComponent(relativePath))
        case .managedFile(let type, let relativePath):
            DocEditorView(
                fileURL:
                    projectURL
                    .appendingPathComponent(type.relativePath, isDirectory: true)
                    .appendingPathComponent(relativePath)
            )
        case .claudeMD:
            DocEditorView(fileURL: ClaudeProjectFiles.claudeMDURL(projectURL: projectURL))
        case .claudeLocalMD:
            DocEditorView(fileURL: ClaudeProjectFiles.claudeLocalMDURL(projectURL: projectURL))
        case .claudeMarkdown(let name):
            DocEditorView(
                fileURL:
                    projectURL
                    .appendingPathComponent(ClaudeProjectFiles.settingsRootRelativePath, isDirectory: true)
                    .appendingPathComponent(name)
            )
        case .mcpJSON:
            DocEditorView(fileURL: ClaudeProjectFiles.mcpJSONURL(projectURL: projectURL))
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
        case .projectSettings:
            ProjectSettingsView(projectURL: projectURL)
        }
    }
}
