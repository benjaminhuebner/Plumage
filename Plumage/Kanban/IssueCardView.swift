import SwiftUI

struct IssueCardView: View {
    let issue: Issue
    let padding: Int

    // Model read, not an env value: re-assigning an env value at the window
    // root re-evaluated the whole detail subtree twice per highlight.
    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHighlighted: Bool {
        kanban.highlightedIssueID == issue.folderName
    }

    private var accessibilityDescription: String {
        var parts = ["\(issue.type.rawValue.capitalized) · \(issue.title)"]
        if let goal = issue.goal, !goal.isEmpty {
            parts.append(goal)
        }
        parts.append(issue.status.label)
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                IssueTypePill(type: issue.type)
                Spacer()
                Image("FeatherGlyph")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(issue.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let goal = issue.goal, !goal.isEmpty {
                Text(goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack {
                Text(IssueIDFormatter.padded(issue.id, width: padding))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(issue.status.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        // Uniform card content height so every card matches. Title + goal
        // (each capped at their lineLimit) plus the Spacer fill any leftover
        // space, so a card with no goal is the same height as one with a
        // long goal.
        .frame(height: KanbanLayout.cardContentHeight, alignment: .top)
        .cardSurface(tint: issue.type.color)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isHighlighted ? 1.0 : 0.0)
                .animation(reduceMotion ? nil : .easeOut(duration: 1.0), value: isHighlighted)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Opens issue detail")
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
                goal: nil
            ),
            padding: 5
        )
        IssueCardView(
            issue: Issue(
                id: 5,
                folderName: "00005-kanban",
                title: "Kanban grouping with a long title that wraps onto a second line",
                type: .feature,
                status: .inProgress,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00005-kanban",
                labels: ["feature", "v0.1"],
                goal: "Bring Kanban columns to life with type-tinted pills and a goal subtitle."
            ),
            padding: 5
        )
        IssueCardView(
            issue: Issue(
                id: 12,
                folderName: "00012-long-goal",
                title: "Long-goal card",
                type: .spike,
                status: .approved,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00012-long-goal",
                labels: [],
                goal: String(
                    repeating:
                        "Lots of context to flow across multiple visible lines so the truncation logic kicks in. ",
                    count: 4
                )
            ),
            padding: 5
        )
        IssueCardView(
            issue: Issue(
                id: 42,
                folderName: "00042-blocked",
                title: "Blocked card",
                type: .refactor,
                status: .blocked,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00042-blocked",
                labels: [],
                goal: "Stuck on an external decision."
            ),
            padding: 5
        )
    }
    .padding()
    .frame(width: 280)
    .environment(ProjectKanbanModel())
}
