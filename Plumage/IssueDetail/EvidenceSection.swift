import SwiftUI

nonisolated enum EvidenceState: Equatable, Sendable {
    case missing
    case unreadable(EvidenceParseError)
    case loaded(RunEvidence)
}

struct EvidenceSection: View {
    let state: EvidenceState
    var isStale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evidence")
                        .font(.headline)
                    if case .loaded(let evidence) = state {
                        Text(Self.summary(for: evidence))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            switch state {
            case .missing:
                Text("No verification evidence recorded for this branch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .unreadable(let error):
                unreadableBanner(error)
            case .loaded(let evidence):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(evidence.tasks, id: \.task) { record in
                        row(
                            icon: record.passedAt != nil
                                ? "checkmark.circle.fill" : "exclamationmark.circle",
                            iconStyle: record.passedAt != nil ? Color.green : Color.orange,
                            title: "Task \(record.task)",
                            passedAt: record.passedAt,
                            attempts: record.attempts,
                            flags: record.flags
                        )
                    }
                    if let finalGate = evidence.finalGate {
                        row(
                            icon: finalGate.passedAt != nil
                                ? "checkmark.seal.fill" : "exclamationmark.circle",
                            iconStyle: finalGate.passedAt != nil ? Color.green : Color.orange,
                            title: "Final gate",
                            passedAt: finalGate.passedAt,
                            attempts: finalGate.attempts,
                            flags: finalGate.flags
                        )
                    }
                    if isStale {
                        stalenessHint
                    }
                }
            }
        }
    }

    private var stalenessHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Changes after last gate — evidence may be stale.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    static func summary(for evidence: RunEvidence) -> String {
        let passed = evidence.tasks.count { $0.passedAt != nil }
        let total = evidence.totalTasks ?? max(passed, evidence.tasks.count)
        var summary = "\(passed)/\(total) tasks gated green"
        if evidence.finalGate?.passedAt != nil {
            summary += " · final gate passed"
        }
        return summary
    }

    private func row(
        icon: String,
        iconStyle: Color,
        title: String,
        passedAt: Date?,
        attempts: Int,
        flags: [String]
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconStyle)
            Text(title)
            if let passedAt {
                Text(passedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            } else {
                Text("not passed")
                    .foregroundStyle(.orange)
            }
            Text(attempts == 1 ? "1 attempt" : "\(attempts) attempts")
                .foregroundStyle(.secondary)
            ForEach(displayFlags(flags), id: \.self) { flag in
                Text(flag)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func displayFlags(_ flags: [String]) -> [String] {
        flags.filter { $0 == "--skip-build" || $0 == "--full" }
            .map { String($0.dropFirst(2)) }
    }

    private func unreadableBanner(_ error: EvidenceParseError) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Evidence unreadable — \(error.summary)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("Loaded, all green") {
    EvidenceSection(
        state: .loaded(
            RunEvidence(
                version: 1,
                issue: "00042-add-user-auth",
                branch: "issue/00042-add-user-auth",
                totalTasks: 3,
                tasks: [
                    RunEvidence.TaskRecord(
                        task: 1, attempts: 1, passedAt: .now, head: "abc", flags: ["--first-commit"]),
                    RunEvidence.TaskRecord(
                        task: 2, attempts: 3, passedAt: .now, head: "def", flags: ["--skip-build"]),
                    RunEvidence.TaskRecord(
                        task: 3, attempts: 1, passedAt: .now, head: "0a1", flags: []),
                ],
                finalGate: RunEvidence.FinalGateRecord(
                    attempts: 1, passedAt: .now, head: "0a1", flags: ["--full"])
            ))
    )
    .padding()
    .frame(width: 600)
}

#Preview("Loaded, degraded") {
    EvidenceSection(
        state: .loaded(
            RunEvidence(
                version: 1,
                issue: "00042-add-user-auth",
                branch: nil,
                totalTasks: 5,
                tasks: [
                    RunEvidence.TaskRecord(
                        task: 1, attempts: 1, passedAt: .now, head: "abc", flags: []),
                    RunEvidence.TaskRecord(
                        task: 2, attempts: 2, passedAt: nil, head: nil, flags: []),
                ],
                finalGate: nil
            ))
    )
    .padding()
    .frame(width: 600)
}

#Preview("Stale") {
    EvidenceSection(
        state: .loaded(
            RunEvidence(
                version: 1,
                issue: "00042-add-user-auth",
                branch: "issue/00042-add-user-auth",
                totalTasks: 2,
                tasks: [
                    RunEvidence.TaskRecord(
                        task: 1, attempts: 1, passedAt: .now, head: "abc", flags: []),
                    RunEvidence.TaskRecord(
                        task: 2, attempts: 1, passedAt: .now, head: "def", flags: []),
                ],
                finalGate: RunEvidence.FinalGateRecord(
                    attempts: 1, passedAt: .now, head: "def", flags: ["--full"])
            )),
        isStale: true
    )
    .padding()
    .frame(width: 600)
}

#Preview("Missing") {
    EvidenceSection(state: .missing)
        .padding()
        .frame(width: 600)
}

#Preview("Unreadable") {
    EvidenceSection(state: .unreadable(.invalidJSON(message: "truncated")))
        .padding()
        .frame(width: 600)
}
