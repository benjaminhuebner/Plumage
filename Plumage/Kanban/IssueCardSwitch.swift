import SwiftUI

struct IssueCardSwitch: View {
    let issue: DiscoveredIssue
    let padding: Int
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @FocusedValue(\.specEditorDirtyFolderName) private var dirtyFolderName: String?
    @State private var dropEdge: DropEdge?
    @State private var measuredHeight: CGFloat = 0

    private enum DropEdge { case above, below }

    var body: some View {
        switch issue {
        case .valid(let value):
            validBody(value)
        case .invalid(let folder, let error):
            NavigationLink(value: SpecRoute.spec(folderName: issue.id)) {
                InvalidIssueCardView(folder: folder, error: error, padding: padding)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func validBody(_ value: Issue) -> some View {
        let isLocked = dirtyFolderName == value.folderName
        let payload = IssueDragPayload(folderName: value.folderName, currentStatus: value.status)

        NavigationLink(value: SpecRoute.spec(folderName: value.folderName)) {
            IssueCardView(issue: value, padding: padding)
                .opacity(isLocked ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .help(isLocked ? "Card has unsaved edits in the editor" : "")
        .overlay(alignment: .top) {
            if dropEdge == .above { DropIndicator() }
        }
        .overlay(alignment: .bottom) {
            if dropEdge == .below { DropIndicator() }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            measuredHeight = height
        }
        .modifier(ConditionalDraggable(payload: payload, enabled: !isLocked))
        .dropDestination(for: IssueDragPayload.self) { items, location in
            dropEdge = nil
            guard let dropped = items.first else { return false }
            let pivot = measuredHeight > 0 ? measuredHeight / 2 : cardHeightFallback / 2
            let edge: DropEdge = location.y < pivot ? .above : .below
            let target: ProjectKanbanModel.DropTarget =
                edge == .above
                ? .aboveCard(folderName: value.folderName, column: value.column)
                : .belowCard(folderName: value.folderName, column: value.column)
            kanban.dispatchDrop(dropped, to: target, projectURL: projectURL)
            return true
        } isTargeted: { targeted in
            if !targeted {
                dropEdge = nil
            } else if dropEdge == nil {
                dropEdge = .above
            }
        }
    }

    // Used only on the first drop hover before .onGeometryChange has fired
    // once. After that, `measuredHeight` reflects the rendered card.
    private let cardHeightFallback: CGFloat = 120
}

private struct ConditionalDraggable: ViewModifier {
    let payload: IssueDragPayload
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(payload)
        } else {
            content
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
