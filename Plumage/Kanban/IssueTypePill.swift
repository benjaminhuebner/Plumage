import SwiftUI

struct IssueTypePill: View {
    let type: IssueType

    var body: some View {
        Text(type.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(type.foregroundOnTint)
            .background(type.color, in: Capsule())
    }
}

extension IssueType {
    // Pill foregrounds: pure white on the cyan/green tints (dark enough for WCAG),
    // black on yellow/orange (too light for white text). Manually verified Light + Dark.
    var foregroundOnTint: Color {
        switch self {
        case .feature, .refactor: .white
        case .chore, .spike: .black
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 8) {
            IssueTypePill(type: .feature)
            IssueTypePill(type: .chore)
            IssueTypePill(type: .spike)
            IssueTypePill(type: .refactor)
        }
        HStack(spacing: 8) {
            IssueTypePill(type: .feature)
            IssueTypePill(type: .chore)
            IssueTypePill(type: .spike)
            IssueTypePill(type: .refactor)
        }
        .environment(\.colorScheme, .dark)
        .padding(8)
        .background(Color.black)
    }
    .padding()
}
