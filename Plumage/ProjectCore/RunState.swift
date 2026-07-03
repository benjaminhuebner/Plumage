import Foundation

nonisolated struct RunState: Equatable, Sendable, Codable {
    let kind: String
    let runId: String?
    let issue: String?
    let startedAt: Date?
    let agentPid: Int?
    let phase: String?
    let lastProgressAt: Date?
    let branch: String?
    let lastCompletedTask: Int?
    let totalTasks: Int?
}

nonisolated extension RunState {
    enum PhaseKind: Equatable, Sendable {
        case running
        case gate
        case failed
    }

    // Unknown phase strings degrade to .running — the schema allows new
    // values and the UI shows the raw string anyway.
    var phaseKind: PhaseKind {
        guard let phase else { return .running }
        if phase.hasPrefix("failed") { return .failed }
        if phase == "pre-commit-gate" || phase == "writing PR.md" { return .gate }
        return .running
    }

    var taskProgressLabel: String? {
        guard let totalTasks, totalTasks > 0 else { return nil }
        let current = min((lastCompletedTask ?? 0) + 1, totalTasks)
        return "task \(current)/\(totalTasks)"
    }
}
