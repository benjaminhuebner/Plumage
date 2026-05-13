import SwiftUI

struct ValidIssueRowView: View {
    let issue: Issue
    let padding: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(IssueIDFormatter.padded(issue.id, width: padding))
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
            Text(issue.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            IssueTypeBadge(type: issue.type)
        }
    }
}

#Preview {
    List {
        ValidIssueRowView(
            issue: Issue(
                id: 1,
                folder: "00001-walking-skeleton",
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
        ValidIssueRowView(
            issue: Issue(
                id: 42,
                folder: "00042-diff-renderer-spike",
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
