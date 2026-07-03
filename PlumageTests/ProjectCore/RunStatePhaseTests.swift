import Testing

@testable import Plumage

struct RunStatePhaseTests {
    private func makeState(
        phase: String?, lastCompletedTask: Int? = nil, totalTasks: Int? = nil
    ) -> RunState {
        RunState(
            kind: "implement", runId: nil, issue: nil, startedAt: nil, agentPid: nil,
            phase: phase, lastProgressAt: nil, branch: nil,
            lastCompletedTask: lastCompletedTask, totalTasks: totalTasks
        )
    }

    @Test(
        "standard phases classify as running, gate, or failed",
        arguments: [
            ("starting", RunState.PhaseKind.running),
            ("running task 3", .running),
            ("pre-commit-gate", .gate),
            ("writing PR.md", .gate),
            ("failed at task 5", .failed),
        ] as [(String, RunState.PhaseKind)]
    )
    func standardPhases(phase: String, expected: RunState.PhaseKind) {
        #expect(makeState(phase: phase).phaseKind == expected)
    }

    @Test("unknown or missing phase degrades to running")
    func unknownPhase() {
        #expect(makeState(phase: "some future phase").phaseKind == .running)
        #expect(makeState(phase: nil).phaseKind == .running)
    }

    @Test("progress label shows the task in progress")
    func progressLabel() {
        #expect(
            makeState(phase: "running task 3", lastCompletedTask: 2, totalTasks: 7)
                .taskProgressLabel == "task 3/7")
    }

    @Test("progress label starts at task 1 with nothing completed")
    func progressLabelStart() {
        #expect(
            makeState(phase: "starting", lastCompletedTask: 0, totalTasks: 7)
                .taskProgressLabel == "task 1/7")
    }

    @Test("progress label clamps to the total after the last task")
    func progressLabelClamps() {
        #expect(
            makeState(phase: "pre-commit-gate", lastCompletedTask: 7, totalTasks: 7)
                .taskProgressLabel == "task 7/7")
    }

    @Test("missing or zero totals degrade to no label")
    func degradedTotals() {
        #expect(makeState(phase: "starting", totalTasks: nil).taskProgressLabel == nil)
        #expect(makeState(phase: "starting", totalTasks: 0).taskProgressLabel == nil)
    }
}
