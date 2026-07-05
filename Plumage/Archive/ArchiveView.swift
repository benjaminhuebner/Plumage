import SwiftUI

struct ArchiveView: View {
    let projectURL: URL
    let padding: Int

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.openSpec) private var openSpec

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 12)]

    var body: some View {
        Group {
            if kanban.archivedIssues.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .task { await kanban.refreshArchivedIssues(projectURL: projectURL) }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(kanban.archivedIssues, id: \.id) { issue in
                    card(issue)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func card(_ issue: DiscoveredIssue) -> some View {
        cardBody(issue)
            .contentShape(Rectangle())
            .onTapGesture { openSpec(.archivedIssue(folderName: issue.id)) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Open")) {
                openSpec(.archivedIssue(folderName: issue.id))
            }
            .contextMenu {
                ArchiveCardContextMenu(
                    folderName: issue.id,
                    folderURL: IssueLayout.archivedIssueFolder(
                        in: projectURL, folderName: issue.id),
                    projectURL: projectURL
                )
            }
    }

    @ViewBuilder
    private func cardBody(_ issue: DiscoveredIssue) -> some View {
        switch issue {
        case .valid(let value):
            IssueCardView(issue: value, padding: padding, isHighlighted: false)
        case .invalid(let folder, let error):
            InvalidIssueCardView(folder: folder, error: error, padding: padding)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Archived Issues", systemImage: "archivebox")
        } description: {
            Text("Archived issues appear here. Right-click an issue on the board and choose Archive.")
        }
        // Size to content vertically, then center in the pane: the detail
        // container pins top-leading, and a plain ContentUnavailableView fills
        // and would otherwise leave its content clinging near the top edge.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
