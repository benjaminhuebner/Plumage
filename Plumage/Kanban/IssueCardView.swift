import SwiftUI

struct IssueCardView: View {
    let issue: Issue
    let padding: Int
    // Resolved by the wrapper so only the 1-2 cards whose highlight actually
    // flips re-render, instead of every card subscribing to highlightedIssueID.
    let isHighlighted: Bool
    var liveRun: RunState?
    var openBlockers: [ResolvedBlocker] = []
    var availableAction: WorkflowAction?
    var isActionDisabled: Bool = false
    var onRunWorkflow: (WorkflowAction) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.issueTypeCatalog) private var issueTypeCatalog

    private var accessibilityDescription: String {
        var parts = ["\(issue.type.rawValue.capitalized) · \(issue.title)"]
        if let goal = issue.goal, !goal.isEmpty {
            parts.append(goal)
        }
        if !issue.labels.isEmpty {
            parts.append("labels: " + issue.labels.joined(separator: ", "))
        }
        if let liveRun {
            var run = "implement run active"
            if let label = liveRun.taskProgressLabel {
                run += ", \(label)"
            }
            parts.append(run)
        }
        if !openBlockers.isEmpty {
            parts.append("blocked by \(openBlockers.count) open issue(s)")
        }
        parts.append(issue.status.label)
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                IssueTypePill(type: issue.type)
                Spacer()
                if let availableAction {
                    CardWorkflowButton(
                        action: availableAction,
                        isDisabled: isActionDisabled,
                        run: onRunWorkflow
                    )
                }
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
                    // Trade a goal line for the label row; the card height is fixed.
                    .lineLimit(issue.labels.isEmpty ? 3 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            if !issue.labels.isEmpty {
                CardLabelRow(labels: issue.labels)
            }

            HStack {
                Text(IssueIDFormatter.padded(issue.id, width: padding))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                if !openBlockers.isEmpty {
                    OpenBlockerBadge(blockers: openBlockers)
                }
                if let liveRun {
                    RunProgressBadge(state: liveRun)
                }
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
        .cardSurface(tint: issueTypeCatalog.color(for: issue.type))
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

private struct CardWorkflowButton: View {
    let action: WorkflowAction
    let isDisabled: Bool
    let run: (WorkflowAction) -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            run(action)
        } label: {
            Image(systemName: action.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isDisabled
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(IssueWorkflowActionBar.aiGradient)
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !isDisabled ? 1.15 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .disabled(isDisabled)
        .help(isDisabled ? "Card has unsaved edits in the editor" : action.label)
        // Unreachable inside the combined card element anyway — the wrapper's AX action is the path.
        .accessibilityHidden(true)
    }
}

private struct OpenBlockerBadge: View {
    let blockers: [ResolvedBlocker]

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "lock.fill")
                .imageScale(.small)
            Text("\(blockers.count)")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.red)
        .help("Blocked by " + blockers.map(blockerLine).joined(separator: ", "))
        .accessibilityHidden(true)
    }

    private func blockerLine(_ blocker: ResolvedBlocker) -> String {
        guard let id = blocker.id, let title = blocker.title else { return blocker.folderName }
        return "#\(IssueIDFormatter.padded(id, width: 5)) \(title)"
    }
}

private struct RunProgressBadge: View {
    let state: RunState

    var body: some View {
        HStack(spacing: 4) {
            RunActivityDot(
                color: state.phaseKind.color,
                isActive: state.phaseKind == .running
            )
            if let label = state.taskProgressLabel {
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CardLabelRow: View {
    let labels: [String]

    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let shown = CardLabelFit.fitCount(labels: labels, width: availableWidth)
        HStack(spacing: 4) {
            ForEach(Array(labels.prefix(shown).enumerated()), id: \.offset) { _, label in
                LabelChip(text: label)
            }
            if shown < labels.count {
                LabelChip.overflow(count: labels.count - shown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
        .accessibilityHidden(true)
    }
}

// Single-pass truncation: estimate each chip's width and keep the whole chips
// that fit, reserving room for the "+N" pill. Replaces an O(n²) ViewThatFits
// cascade; conservative, so it drops a chip rather than clip on a fixed-width card.
nonisolated enum CardLabelFit {
    static func fitCount(labels: [String], width: CGFloat) -> Int {
        guard width > 0 else { return labels.count }
        let spacing: CGFloat = 4
        let overflowReserve: CGFloat = 34
        var used: CGFloat = 0
        var shown = 0
        for (index, label) in labels.enumerated() {
            let next = used + (shown > 0 ? spacing : 0) + chipWidth(label)
            let reserve = index < labels.count - 1 ? spacing + overflowReserve : 0
            guard next + reserve <= width else { break }
            used = next
            shown += 1
        }
        return shown
    }

    // caption.monospaced ≈ 7pt/char + 12pt padding, capped at LabelChip's own 80pt frame.
    static func chipWidth(_ text: String) -> CGFloat {
        min(CGFloat(text.count) * 7 + 12, 80)
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
            padding: 5,
            isHighlighted: false
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
                labels: ["feature", "v0.1", "ui", "backend", "performance"],
                goal: "Bring Kanban columns to life with type-tinted pills and a goal subtitle."
            ),
            padding: 5,
            isHighlighted: false,
            liveRun: RunState(
                kind: "implement",
                runId: nil,
                issue: "00005-kanban",
                startedAt: .distantPast,
                agentPid: 1,
                phase: "running task 3",
                lastProgressAt: .distantPast,
                branch: "issue/00005-kanban",
                lastCompletedTask: 2,
                totalTasks: 7
            )
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
            padding: 5,
            isHighlighted: false,
            availableAction: .implement
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
            padding: 5,
            isHighlighted: false,
            openBlockers: [
                ResolvedBlocker(folderName: "00007-auth", state: .open, id: 7, title: "User auth"),
                ResolvedBlocker(folderName: "00009-api", state: .open, id: 9, title: "API layer"),
            ]
        )
    }
    .padding()
    .frame(width: 280)
    .environment(ProjectKanbanModel())
}
