import SwiftUI

struct KanbanView: View {
    let grouped: [IssueColumn: [DiscoveredIssue]]
    let padding: Int
    let projectURL: URL

    @State private var cardFrames: [String: CGRect] = [:]
    @State private var columnFrames: [IssueColumn: CGRect] = [:]
    @State private var kanbanDrag = KanbanDragController()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(IssueColumn.allCases) { column in
                    KanbanColumnView(
                        column: column,
                        issues: grouped[column] ?? [],
                        padding: padding,
                        projectURL: projectURL
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .coordinateSpace(name: KanbanCoordinateSpace.name)
        .environment(kanbanDrag)
        .onPreferenceChange(CardFramesPreferenceKey.self) { frames in
            cardFrames = frames
        }
        .onPreferenceChange(ColumnFramesPreferenceKey.self) { frames in
            columnFrames = frames
        }
        .onChange(of: kanbanDrag.state?.cursorLocation) { _, _ in
            updateResolvedTarget()
        }
    }

    private func updateResolvedTarget() {
        guard let drag = kanbanDrag.state else { return }
        let resolved = resolveDropTarget(
            cursor: drag.cursorLocation,
            cardFrames: cardFrames,
            columnFrames: columnFrames,
            sortedIssues: grouped,
            sourceFolderName: drag.sourceFolderName
        )
        if drag.target != resolved {
            withAnimation(.smooth(duration: 0.18)) {
                kanbanDrag.setTarget(resolved)
            }
        }
    }
}

private func kanbanPreviewIssues() -> [DiscoveredIssue] {
    [
        .valid(
            Issue(
                id: 1, folderName: "00001-walking-skeleton", title: "Walking Skeleton",
                type: .chore, status: .done, created: .distantPast, updated: .distantPast,
                branch: "issue/00001-walking-skeleton", labels: ["bootstrap"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 2, folderName: "00002-config", title: "Project config",
                type: .feature, status: .waitingForReview, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00002-config", labels: ["feature", "v0.1"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 3, folderName: "00003-list", title: "List view",
                type: .feature, status: .inProgress, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00003-list", labels: ["feature", "v0.1"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 4, folderName: "00004-discovery", title: "Discovery",
                type: .feature, status: .approved, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00004-discovery", labels: ["feature", "v0.1"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 5, folderName: "00005-kanban", title: "Kanban grouping",
                type: .feature, status: .draft, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00005-kanban", labels: ["feature", "v0.1"], model: nil
            )
        ),
        .invalid(
            folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken"),
            error: .invalidEnumValue(field: "status", value: "aproved")
        ),
    ]
}

#Preview {
    KanbanView(
        grouped: Dictionary(grouping: kanbanPreviewIssues(), by: \.column),
        padding: 5,
        projectURL: URL(filePath: "/tmp/sample")
    )
    .frame(width: 1100, height: 600)
}
