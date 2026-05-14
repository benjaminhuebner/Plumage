import SwiftUI

struct IssueCardSwitch: View {
    let issue: DiscoveredIssue
    let padding: Int
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @State private var topHovered = false
    @State private var bottomHovered = false

    var body: some View {
        NavigationLink(value: SpecRoute.spec(folderName: issue.id)) {
            switch issue {
            case .valid(let value):
                IssueCardView(issue: value, padding: padding)
                    .overlay(alignment: .top) {
                        if topHovered { DropIndicator() }
                    }
                    .overlay(alignment: .bottom) {
                        if bottomHovered { DropIndicator() }
                    }
                    .overlay {
                        VStack(spacing: 0) {
                            dropZone(for: .above, on: value)
                            dropZone(for: .below, on: value)
                        }
                    }
            case .invalid(let folder, let error):
                InvalidIssueCardView(folder: folder, error: error, padding: padding)
            }
        }
        .buttonStyle(.plain)
    }

    private enum DropEdge { case above, below }

    private func dropZone(for edge: DropEdge, on issue: Issue) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .dropDestination(for: IssueDragPayload.self) { items, _ in
                guard let payload = items.first else { return false }
                let target: ProjectKanbanModel.DropTarget =
                    edge == .above
                    ? .aboveCard(folderName: issue.folderName, column: issue.column)
                    : .belowCard(folderName: issue.folderName, column: issue.column)
                let urlSnapshot = projectURL
                Task { @MainActor in
                    await kanban.performDrop(payload, to: target, projectURL: urlSnapshot)
                }
                return true
            } isTargeted: { targeted in
                if edge == .above {
                    topHovered = targeted
                } else {
                    bottomHovered = targeted
                }
            }
    }
}

#Preview {
    NavigationStack {
        VStack(spacing: 8) {
            IssueCardSwitch(
                issue: .valid(
                    Issue(
                        id: 1,
                        folderName: "00001-walking-skeleton",
                        title: "Walking Skeleton",
                        type: .chore,
                        status: .done,
                        created: .distantPast,
                        updated: .distantPast,
                        branch: "issue/00001-walking-skeleton",
                        labels: ["bootstrap"],
                        model: nil
                    )
                ),
                padding: 5,
                projectURL: URL(filePath: "/tmp/sample")
            )
            IssueCardSwitch(
                issue: .invalid(
                    folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken-stuff"),
                    error: .invalidEnumValue(field: "status", value: "aproved")
                ),
                padding: 5,
                projectURL: URL(filePath: "/tmp/sample")
            )
        }
        .padding()
        .frame(width: 260)
    }
    .environment(ProjectKanbanModel())
}
