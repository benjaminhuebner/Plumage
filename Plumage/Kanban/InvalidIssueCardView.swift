import SwiftUI

struct InvalidIssueCardView: View {
    let folder: URL
    let error: FrontmatterError
    let padding: Int

    // See IssueCardView: model read instead of env value keeps highlight
    // invalidation scoped to the cards.
    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folderName: String { folder.lastPathComponent }

    private var parts: (id: Int?, slug: String) {
        IssueDiscovery.extractID(fromFolderName: folderName)
    }

    private var isHighlighted: Bool {
        kanban.highlightedIssueID == folderName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                invalidPill
                Spacer()
                Image("FeatherGlyph")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(parts.slug)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                Text(IssueIDFormatter.paddedOrPlaceholder(parts.id, width: padding))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 3) {
                    if differentiateWithoutColor {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                    }
                    Text("Invalid")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.red)
            }
        }
        // Same uniform card height as IssueCardView.
        .frame(height: KanbanLayout.cardContentHeight, alignment: .top)
        .cardSurface(tint: .red)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.red, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isHighlighted ? 1.0 : 0.0)
                .animation(reduceMotion ? nil : .easeOut(duration: 1.0), value: isHighlighted)
        )
        .contentShape(Rectangle())
        .help("Fix the frontmatter to enable drag & drop — \(error.summary)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Invalid issue: \(error.summary)")
    }

    private var invalidPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
            Text("Invalid")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(Color.red, in: Capsule())
    }
}

#Preview {
    VStack(spacing: 8) {
        InvalidIssueCardView(
            folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken-stuff"),
            error: .invalidEnumValue(field: "status", value: "aproved"),
            padding: 5
        )
        InvalidIssueCardView(
            folder: URL(filePath: "/tmp/sample/.claude/issues/no-id-prefix"),
            error: .missingRequiredField(name: "branch"),
            padding: 5
        )
    }
    .padding()
    .frame(width: 280)
    .environment(ProjectKanbanModel())
}
