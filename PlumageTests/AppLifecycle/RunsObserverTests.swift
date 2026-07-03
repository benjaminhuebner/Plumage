import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("RunCompletionNotifier runs observers")
struct RunsObserverTests {
    private func makeNotifier() -> RunCompletionNotifier {
        RunCompletionNotifier(
            isFrontmost: { true },
            post: { _, _, _, _, _ in }
        )
    }

    @Test("registered observer fires on a runs event for its root")
    func observerFires() {
        let notifier = makeNotifier()
        let root = URL(filePath: "/tmp/project-a")
        var fired = 0
        notifier.addRunsObserver(root: root, id: UUID()) { fired += 1 }

        notifier.checkFinished(root: root)

        #expect(fired == 1)
    }

    @Test("observer does not fire for a different root")
    func observerScopedToRoot() {
        let notifier = makeNotifier()
        var fired = 0
        notifier.addRunsObserver(root: URL(filePath: "/tmp/project-a"), id: UUID()) { fired += 1 }

        notifier.checkFinished(root: URL(filePath: "/tmp/project-b"))

        #expect(fired == 0)
    }

    @Test("removed observer no longer fires")
    func removedObserverSilent() {
        let notifier = makeNotifier()
        let root = URL(filePath: "/tmp/project-a")
        let id = UUID()
        var fired = 0
        notifier.addRunsObserver(root: root, id: id) { fired += 1 }
        notifier.removeRunsObserver(root: root, id: id)

        notifier.checkFinished(root: root)

        #expect(fired == 0)
    }

    @Test("multiple observers on one root all fire")
    func multipleObservers() {
        let notifier = makeNotifier()
        let root = URL(filePath: "/tmp/project-a")
        var first = 0
        var second = 0
        notifier.addRunsObserver(root: root, id: UUID()) { first += 1 }
        notifier.addRunsObserver(root: root, id: UUID()) { second += 1 }

        notifier.checkFinished(root: root)

        #expect(first == 1)
        #expect(second == 1)
    }

    @Test("watchedRoots falls back to the queried root when nothing is watched")
    func watchedRootsFallback() {
        let notifier = makeNotifier()
        let root = URL(filePath: "/tmp/project-a")

        #expect(notifier.watchedRoots(forRoot: root) == [root])
    }
}
