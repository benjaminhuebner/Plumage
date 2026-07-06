import SwiftUI

struct RunHistorySection: View {
    let page: RunHistoryReader.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run History")
                .font(.headline)
            ForEach(Array(page.records.enumerated()), id: \.offset) { _, record in
                RunHistoryRow(record: record)
            }
            if page.totalCount > page.records.count {
                Text("showing latest \(page.records.count) of \(page.totalCount) runs")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

private struct RunHistoryRow: View {
    let record: RunHistoryRecord

    private var timespan: String {
        let started = record.state.startedAt.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        }
        let ended = record.finishedAt.map {
            $0.formatted(date: .omitted, time: .shortened)
        }
        switch (started, ended) {
        case (let started?, let ended?): return "\(started) – \(ended)"
        case (let started?, nil): return started
        case (nil, let ended?): return "ended \(ended)"
        case (nil, nil): return "—"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(record.outcome ?? "unknown")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(record.outcomeKind.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(record.outcomeKind.color.opacity(0.15)))
            Text(timespan)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let total = record.state.totalTasks, total > 0 {
                Text("\(record.state.lastCompletedTask ?? 0)/\(total) tasks")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RunHistorySection(
        page: RunHistoryReader.Page(
            records: [
                RunHistoryRecord(
                    state: RunState(
                        kind: "implement", runId: nil, issue: "00042-add-user-auth",
                        startedAt: .now.addingTimeInterval(-7200), agentPid: 0,
                        phase: "writing PR.md", lastProgressAt: .now, branch: nil,
                        lastCompletedTask: 9, totalTasks: 9
                    ),
                    finishedAt: .now,
                    outcome: "completed"
                ),
                RunHistoryRecord(
                    state: RunState(
                        kind: "implement", runId: nil, issue: "00042-add-user-auth",
                        startedAt: .now.addingTimeInterval(-90000), agentPid: 0,
                        phase: "failed at task 5", lastProgressAt: nil, branch: nil,
                        lastCompletedTask: 4, totalTasks: 9
                    ),
                    finishedAt: .now.addingTimeInterval(-86400),
                    outcome: "failed at task 5"
                ),
                RunHistoryRecord(
                    state: RunState(
                        kind: "implement", runId: nil, issue: "00042-add-user-auth",
                        startedAt: .now.addingTimeInterval(-180000), agentPid: 0,
                        phase: "running task 2", lastProgressAt: nil, branch: nil,
                        lastCompletedTask: 1, totalTasks: 9
                    ),
                    finishedAt: .now.addingTimeInterval(-172800),
                    outcome: "crashed"
                ),
            ],
            totalCount: 25
        )
    )
    .frame(width: 640)
    .padding()
}
