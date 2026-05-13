import SwiftUI

struct IssueCardSwitch: View {
    let issue: DiscoveredIssue
    let padding: Int

    var body: some View {
        switch issue {
        case .valid(let value):
            IssueCardView(issue: value, padding: padding)
        case .invalid(let folder, let error):
            InvalidIssueCardView(folder: folder, error: error, padding: padding)
        }
    }
}

#Preview {
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
            padding: 5
        )
        IssueCardSwitch(
            issue: .invalid(
                folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken-stuff"),
                error: .invalidEnumValue(field: "status", value: "aproved")
            ),
            padding: 5
        )
    }
    .padding()
    .frame(width: 260)
}
