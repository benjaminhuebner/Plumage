import SwiftUI

struct IssueDetailHero: View {
    let issue: Issue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IssueStatusPill(status: issue.status)
                IssueTypePill(type: issue.type)
                if !issue.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(issue.labels, id: \.self) { label in
                            LabelChip(text: label)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Text(issue.title)
                .font(.largeTitle.weight(.bold))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    IssueDetailHero(
        issue: Issue(
            id: 16,
            folderName: "00016-better-issue-details",
            title: "Better Issue-Details View",
            type: .feature,
            status: .inProgress,
            created: .distantPast,
            updated: .distantPast,
            branch: "issue/00016-better-issue-details",
            labels: ["ui", "ux"],
            model: nil
        )
    )
    .padding()
    .frame(width: 600)
}
