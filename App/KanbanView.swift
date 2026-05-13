import SwiftUI

struct KanbanView: View {
    let issues: [DiscoveredIssue]
    let padding: Int

    private var grouped: [IssueColumn: [DiscoveredIssue]] {
        Dictionary(grouping: issues, by: \.column)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(IssueColumn.allCases) { column in
                    KanbanColumnView(
                        column: column,
                        issues: grouped[column] ?? [],
                        padding: padding
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    KanbanView(
        issues: [
            .valid(
                Issue(
                    id: 1, folder: "00001-walking-skeleton", title: "Walking Skeleton",
                    type: .chore, status: .done, created: .distantPast, updated: .distantPast,
                    branch: "issue/00001-walking-skeleton", labels: ["bootstrap"], model: nil
                )
            ),
            .valid(
                Issue(
                    id: 2, folder: "00002-config", title: "Project config",
                    type: .feature, status: .waitingForReview, created: .distantPast,
                    updated: .distantPast,
                    branch: "issue/00002-config", labels: ["feature", "v0.1"], model: nil
                )
            ),
            .valid(
                Issue(
                    id: 3, folder: "00003-list", title: "List view",
                    type: .feature, status: .inProgress, created: .distantPast,
                    updated: .distantPast,
                    branch: "issue/00003-list", labels: ["feature", "v0.1"], model: nil
                )
            ),
            .valid(
                Issue(
                    id: 4, folder: "00004-discovery", title: "Discovery",
                    type: .feature, status: .approved, created: .distantPast,
                    updated: .distantPast,
                    branch: "issue/00004-discovery", labels: ["feature", "v0.1"], model: nil
                )
            ),
            .valid(
                Issue(
                    id: 5, folder: "00005-kanban", title: "Kanban grouping",
                    type: .feature, status: .draft, created: .distantPast,
                    updated: .distantPast,
                    branch: "issue/00005-kanban", labels: ["feature", "v0.1"], model: nil
                )
            ),
            .invalid(
                folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken"),
                error: .invalidEnumValue(field: "status", value: "aproved")
            ),
        ],
        padding: 5
    )
    .frame(width: 1100, height: 600)
}
