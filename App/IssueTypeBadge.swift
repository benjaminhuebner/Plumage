import SwiftUI

struct IssueTypeBadge: View {
    let type: IssueType

    var body: some View {
        Text(type.rawValue)
            .font(.caption.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(type.color.opacity(0.25), in: Capsule())
            .foregroundStyle(type.color)
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
