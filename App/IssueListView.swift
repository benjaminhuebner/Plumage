import SwiftUI

struct IssueListView: View {
    let issues: [DiscoveredIssue]
    let padding: Int

    var body: some View {
        List(issues) { item in
            IssueRowView(issue: item, padding: padding)
        }
    }
}

#Preview {
    IssueListView(
        issues: [
            .valid(
                Issue(
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
                )
            ),
            .invalid(
                folder: URL(filePath: "/tmp/sample/.claude/issues/00003-broken"),
                error: .invalidEnumValue(field: "status", value: "aproved")
            ),
        ],
        padding: 5
    )
}
