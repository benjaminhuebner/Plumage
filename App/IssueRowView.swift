import SwiftUI

struct IssueRowView: View {
    let issue: DiscoveredIssue
    let padding: Int

    var body: some View {
        switch issue {
        case .valid(let value):
            ValidIssueRowView(issue: value, padding: padding)
        case .invalid(let folder, let error):
            InvalidIssueRowView(folder: folder, error: error, padding: padding)
        }
    }
}

#Preview {
    List {
        IssueRowView(
            issue: .valid(
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
            padding: 5
        )
        IssueRowView(
            issue: .invalid(
                folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken-stuff"),
                error: .invalidEnumValue(field: "status", value: "aproved")
            ),
            padding: 5
        )
        IssueRowView(
            issue: .invalid(
                folder: URL(filePath: "/tmp/sample/.claude/issues/no-id-prefix"),
                error: .missingFrontmatter
            ),
            padding: 5
        )
    }
}
