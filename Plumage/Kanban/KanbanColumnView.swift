import SwiftUI

struct KanbanColumnView: View {
    let column: IssueColumn
    let issues: [DiscoveredIssue]
    let padding: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.name)
                .font(.headline)
                .padding(.horizontal, 4)

            if issues.isEmpty {
                Text("No issues")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(issues) { item in
                            IssueCardSwitch(issue: item, padding: padding)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .frame(minWidth: 240, maxWidth: 280, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    HStack(alignment: .top, spacing: 12) {
        KanbanColumnView(
            column: .todo,
            issues: [
                .valid(
                    Issue(
                        id: 1,
                        folderName: "00001-walking-skeleton",
                        title: "Walking Skeleton",
                        type: .chore,
                        status: .approved,
                        created: .distantPast,
                        updated: .distantPast,
                        branch: "issue/00001-walking-skeleton",
                        labels: ["bootstrap"],
                        model: nil
                    )
                ),
                .valid(
                    Issue(
                        id: 7,
                        folderName: "00007-blocked-thing",
                        title: "Something blocked by another team",
                        type: .feature,
                        status: .blocked,
                        created: .distantPast,
                        updated: .distantPast,
                        branch: "issue/00007-blocked-thing",
                        labels: ["feature", "v0.1"],
                        model: nil
                    )
                ),
                .invalid(
                    folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken"),
                    error: .invalidEnumValue(field: "status", value: "aproved")
                ),
            ],
            padding: 5
        )
        KanbanColumnView(
            column: .done,
            issues: [],
            padding: 5
        )
    }
    .padding()
    .frame(height: 480)
}
