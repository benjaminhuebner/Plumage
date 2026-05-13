import SwiftUI

struct IssueTypeBadge: View {
    let type: IssueType

    var body: some View {
        Text(type.rawValue)
            .font(.caption.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.primary)
            .background(
                Capsule()
                    .fill(type.color.opacity(0.18))
                    .stroke(type.color.opacity(0.55), lineWidth: 0.5)
            )
    }
}

#Preview {
    HStack(spacing: 8) {
        IssueTypeBadge(type: .feature)
        IssueTypeBadge(type: .chore)
        IssueTypeBadge(type: .spike)
    }
    .padding()
}
