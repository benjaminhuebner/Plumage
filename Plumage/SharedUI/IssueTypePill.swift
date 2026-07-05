import SwiftUI

struct IssueTypePill: View {
    let type: IssueType

    @Environment(\.issueTypeCatalog) private var catalog

    var body: some View {
        Text(type.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(catalog.foregroundOnTint(for: type))
            .background(catalog.color(for: type), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Type: \(type.rawValue.capitalized)")
    }
}

extension IssueType {
    // Pill foregrounds: pure white on the cyan/green tints (dark enough for WCAG),
    // black on yellow/orange (too light for white text). Custom types sit on the
    // adaptive label palette, which pairs with primary text (LabelChip precedent).
    var foregroundOnTint: Color {
        switch self {
        case .feature, .refactor: .white
        case .chore, .spike: .black
        default: .primary
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
