import SwiftUI

struct IssueRowView: View {
    let issue: Issue
    let padding: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(paddedId)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
            Text(issue.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            IssueTypeBadge(type: issue.type)
        }
    }

    private var paddedId: String {
        String(format: "%0\(max(padding, 1))d", issue.id)
    }
}

#Preview {
    List {
        IssueRowView(
            issue: Issue(
                id: 1,
                title: "Walking Skeleton",
                type: .chore,
                status: .done,
                created: .now,
                updated: .now,
                branch: "issue/00001-walking-skeleton",
                labels: [],
                model: nil
            ),
            padding: 5
        )
        IssueRowView(
            issue: Issue(
                id: 2,
                title: "Open Project Flow",
                type: .feature,
                status: .done,
                created: .now,
                updated: .now,
                branch: "issue/00002-open-project",
                labels: ["feature"],
                model: nil
            ),
            padding: 5
        )
        IssueRowView(
            issue: Issue(
                id: 42,
                title: "Investigate diff renderer performance with very long lines",
                type: .spike,
                status: .draft,
                created: .now,
                updated: .now,
                branch: "issue/00042-diff-renderer-spike",
                labels: [],
                model: nil
            ),
            padding: 5
        )
    }
}
