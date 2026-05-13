import SwiftUI

struct IssueCardView: View {
    let issue: Issue
    let padding: Int

    private let maxVisibleLabels = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.title)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Text(IssueIDFormatter.padded(issue.id, width: padding))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if issue.status == .blocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help("Blocked")
                }
                IssueTypeBadge(type: issue.type)
            }

            if !issue.labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(issue.labels.prefix(maxVisibleLabels), id: \.self) { label in
                        LabelChip(text: label)
                    }
                    if issue.labels.count > maxVisibleLabels {
                        LabelChip.overflow(count: issue.labels.count - maxVisibleLabels)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

#Preview {
    VStack(spacing: 8) {
        IssueCardView(
            issue: Issue(
                id: 1,
                folderName: "00001-walking-skeleton",
                title: "Walking Skeleton",
                type: .chore,
                status: .done,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00001-walking-skeleton",
                labels: [],
                model: nil
            ),
            padding: 5
        )
        IssueCardView(
            issue: Issue(
                id: 5,
                folderName: "00005-kanban",
                title: "Kanban grouping with label chips and a long title that wraps",
                type: .feature,
                status: .inProgress,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00005-kanban",
                labels: ["feature", "v0.1", "ui"],
                model: nil
            ),
            padding: 5
        )
        IssueCardView(
            issue: Issue(
                id: 12,
                folderName: "00012-many-labels",
                title: "Issue with more labels than the card can show inline",
                type: .feature,
                status: .approved,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00012-many-labels",
                labels: ["a", "b", "c", "d", "e", "f"],
                model: nil
            ),
            padding: 5
        )
        IssueCardView(
            issue: Issue(
                id: 42,
                folderName: "00042-blocked",
                title: "Blocked card shows a lock symbol",
                type: .feature,
                status: .blocked,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00042-blocked",
                labels: ["bootstrap"],
                model: nil
            ),
            padding: 5
        )
    }
    .padding()
    .frame(width: 260)
}
