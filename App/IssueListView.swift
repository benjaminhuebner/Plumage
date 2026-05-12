import SwiftUI

struct IssueListView: View {
    let issues: [Issue]
    let padding: Int

    var body: some View {
        List(issues, id: \.folder) { issue in
            IssueRowView(issue: issue, padding: padding)
        }
    }
}

#Preview {
    IssueListView(
        issues: [
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
            ),
            Issue(
                id: 3,
                folder: "00003-issue-list",
                title: "Issue list",
                type: .feature,
                status: .inProgress,
                created: .now,
                updated: .now,
                branch: "issue/00003-issue-list",
                labels: [],
                model: nil
            ),
        ],
        padding: 5
    )
}
