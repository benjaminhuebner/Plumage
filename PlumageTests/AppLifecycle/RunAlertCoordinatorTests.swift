import Foundation
import Testing

@testable import Plumage

@Suite("RunAlertCoordinator attention gating")
struct RunAlertCoordinatorTests {
    @Test("alerts only when backgrounded with a live run")
    func pureGating() {
        #expect(RunAlertCoordinator.shouldAlert(isFrontmost: false, hasLiveRun: true))
        #expect(!RunAlertCoordinator.shouldAlert(isFrontmost: true, hasLiveRun: true))
        #expect(!RunAlertCoordinator.shouldAlert(isFrontmost: false, hasLiveRun: false))
        #expect(!RunAlertCoordinator.shouldAlert(isFrontmost: true, hasLiveRun: false))
    }

    @MainActor
    private func makeCoordinator(
        frontmost: Bool, live: Bool, onAlert: @escaping @MainActor () -> Void
    ) -> RunAlertCoordinator {
        RunAlertCoordinator(
            signalURL: URL(filePath: "/tmp/unused-\(UUID().uuidString)"),
            isFrontmost: { frontmost },
            hasLiveRun: { _ in live },
            requestAttention: onAlert
        )
    }

    private func sampleSignal() -> AgentNotificationSignal {
        AgentNotificationSignal(
            sessionID: "s", cwd: "/p", notificationType: "idle_prompt", message: nil)
    }

    @MainActor
    @Test("backgrounded + live run bounces the dock")
    func bouncesWhenBackgrounded() {
        var alerts = 0
        let coordinator = makeCoordinator(frontmost: false, live: true) { alerts += 1 }
        #expect(coordinator.handle(sampleSignal()))
        #expect(alerts == 1)
    }

    @MainActor
    @Test("frontmost suppresses the bounce")
    func suppressedWhenFrontmost() {
        var alerts = 0
        let coordinator = makeCoordinator(frontmost: true, live: true) { alerts += 1 }
        #expect(!coordinator.handle(sampleSignal()))
        #expect(alerts == 0)
    }

    @MainActor
    @Test("a signal without a live run is ignored")
    func suppressedWhenStale() {
        var alerts = 0
        let coordinator = makeCoordinator(frontmost: false, live: false) { alerts += 1 }
        #expect(!coordinator.handle(sampleSignal()))
        #expect(alerts == 0)
    }
}
