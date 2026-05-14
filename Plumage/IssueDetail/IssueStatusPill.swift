import SwiftUI

struct IssueStatusPill: View {
    let status: IssueStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.indicatorColor)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.indicatorColor.opacity(0.18), in: Capsule())
        .overlay(
            Capsule().strokeBorder(status.indicatorColor.opacity(0.45), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }
}

extension IssueStatus {
    var indicatorColor: Color {
        switch self {
        case .draft: .gray
        case .approved: .blue
        case .inProgress: .yellow
        case .waitingForReview: .purple
        case .done: .green
        case .blocked: .red
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        IssueStatusPill(status: .draft)
        IssueStatusPill(status: .approved)
        IssueStatusPill(status: .inProgress)
        IssueStatusPill(status: .waitingForReview)
        IssueStatusPill(status: .done)
        IssueStatusPill(status: .blocked)
    }
    .padding()
    .frame(width: 200)
}
