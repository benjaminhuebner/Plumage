import Foundation
import Testing

@testable import Plumage

@Suite("RunAlertCoordinator attention gating")
struct RunAlertCoordinatorTests {
    @Test("alerts whenever backgrounded, regardless of any run")
    func pureGating() {
        #expect(RunAlertCoordinator.shouldAlert(isFrontmost: false))
        #expect(!RunAlertCoordinator.shouldAlert(isFrontmost: true))
    }

    @MainActor
    private func makeCoordinator(
        frontmost: Bool, onAlert: @escaping @MainActor () -> Void
    ) -> RunAlertCoordinator {
        RunAlertCoordinator(
            signalURL: URL(filePath: "/tmp/unused-\(UUID().uuidString)"),
            isFrontmost: { frontmost },
            requestAttention: onAlert
        )
    }

    private func sampleSignal(cwd: String = "/p") -> AgentNotificationSignal {
        AgentNotificationSignal(
            sessionID: "s", cwd: cwd, notificationType: "idle_prompt", message: nil)
    }

    @MainActor
    @Test("backgrounded bounces the dock")
    func bouncesWhenBackgrounded() {
        var alerts = 0
        let coordinator = makeCoordinator(frontmost: false) { alerts += 1 }
        #expect(coordinator.handle(sampleSignal()))
        #expect(alerts == 1)
    }

    @MainActor
    @Test("frontmost suppresses the bounce")
    func suppressedWhenFrontmost() {
        var alerts = 0
        let coordinator = makeCoordinator(frontmost: true) { alerts += 1 }
        #expect(!coordinator.handle(sampleSignal()))
        #expect(alerts == 0)
    }

    @MainActor
    @Test("a backgrounded session with no implement run still bounces")
    func bouncesWithoutImplementRun() {
        // The gate no longer requires a live implement run — plan/review/ad-hoc
        // sessions (which never create run-state) must still pull the user back.
        var alerts = 0
        let coordinator = makeCoordinator(frontmost: false) { alerts += 1 }
        #expect(coordinator.handle(sampleSignal(cwd: "/some/other/checkout")))
        #expect(alerts == 1)
    }
}
