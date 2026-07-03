import SwiftUI

struct RunStatusStrip: View {
    let state: RunState
    let isWorktree: Bool
    let onShowTerminal: () -> Void

    private var phaseText: String {
        let phase = state.phase ?? "running"
        if phase.hasPrefix("running task"), let label = state.taskProgressLabel {
            return "running \(label)"
        }
        return phase
    }

    var body: some View {
        HStack(spacing: 8) {
            RunActivityDot(
                color: state.phaseKind.color,
                isActive: state.phaseKind == .running,
                size: 8
            )
            Text(phaseText)
                .font(.callout.weight(.medium))
            if isWorktree {
                Text("worktree")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            if let lastProgress = state.lastProgressAt {
                Text("last progress \(Text(lastProgress, style: .relative)) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onShowTerminal()
            } label: {
                Label("Show Terminal", systemImage: "terminal")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
        // .contain, not .combine: combining would swallow the button and
        // remove it from the accessibility tree.
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: 12) {
        RunStatusStrip(
            state: RunState(
                kind: "implement", runId: nil, issue: "00042-add-user-auth",
                startedAt: .now, agentPid: 1, phase: "running task 4",
                lastProgressAt: .now.addingTimeInterval(-125),
                branch: "issue/00042-add-user-auth", lastCompletedTask: 3, totalTasks: 9
            ),
            isWorktree: false,
            onShowTerminal: {}
        )
        RunStatusStrip(
            state: RunState(
                kind: "implement", runId: nil, issue: "00042-add-user-auth",
                startedAt: .now, agentPid: 1, phase: "pre-commit-gate",
                lastProgressAt: .now.addingTimeInterval(-30),
                branch: "issue/00042-add-user-auth", lastCompletedTask: 9, totalTasks: 9
            ),
            isWorktree: true,
            onShowTerminal: {}
        )
        RunStatusStrip(
            state: RunState(
                kind: "implement", runId: nil, issue: "00042-add-user-auth",
                startedAt: .now, agentPid: 1, phase: "failed at task 5",
                lastProgressAt: .now.addingTimeInterval(-3600),
                branch: "issue/00042-add-user-auth", lastCompletedTask: 4, totalTasks: 9
            ),
            isWorktree: false,
            onShowTerminal: {}
        )
    }
    .frame(width: 640)
    .padding()
}
