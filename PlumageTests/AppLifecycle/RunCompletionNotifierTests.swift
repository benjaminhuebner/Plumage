import Foundation
import Testing

@testable import Plumage

@Suite("RunCompletionNotifier")
struct RunCompletionNotifierTests {
    @Test("posts only when backgrounded and authorized")
    func gating() {
        #expect(RunCompletionNotifier.shouldPost(isFrontmost: false, authorized: true))
        #expect(!RunCompletionNotifier.shouldPost(isFrontmost: true, authorized: true))
        #expect(!RunCompletionNotifier.shouldPost(isFrontmost: false, authorized: false))
        #expect(!RunCompletionNotifier.shouldPost(isFrontmost: true, authorized: false))
    }

    @Test("finished slugs are the runs that disappeared (parallel-safe)")
    func finishedDetection() {
        #expect(
            RunCompletionNotifier.finishedSlugs(was: ["00001-a", "00002-b"], now: ["00002-b"])
                == ["00001-a"])
        #expect(RunCompletionNotifier.finishedSlugs(was: ["00001-a"], now: ["00001-a"]).isEmpty)
        #expect(RunCompletionNotifier.finishedSlugs(was: [], now: ["00003-c"]).isEmpty)
    }

    @MainActor
    @Test("runFinished posts the named banner when backgrounded")
    func postsWhenBackgrounded() {
        var posted: (title: String, slug: String)?
        let notifier = RunCompletionNotifier(
            isFrontmost: { false },
            post: { title, slug, _, _ in posted = (title, slug) })
        let didPost = notifier.runFinished(
            title: "Add Foo", slug: "00001-a", projectRoot: URL(filePath: "/p"))
        #expect(didPost)
        #expect(posted?.title == "Add Foo")
        #expect(posted?.slug == "00001-a")
    }

    @MainActor
    @Test("runFinished is suppressed while frontmost")
    func suppressedWhenFrontmost() {
        var postCount = 0
        let notifier = RunCompletionNotifier(
            isFrontmost: { true },
            post: { _, _, _, _ in postCount += 1 })
        #expect(!notifier.runFinished(title: "X", slug: "s", projectRoot: URL(filePath: "/p")))
        #expect(postCount == 0)
    }

    @MainActor
    @Test("runFinished is suppressed when not authorized")
    func suppressedWhenUnauthorized() {
        // Default init leaves authorized = false; shouldPost short-circuits
        // before the real banner path runs.
        let notifier = RunCompletionNotifier(isFrontmost: { false })
        #expect(!notifier.runFinished(title: "X", slug: "s", projectRoot: URL(filePath: "/p")))
    }

    @MainActor
    @Test("a second run of the same slug gets a distinct notification identifier")
    func distinctIdentifiersPerRun() {
        var ids: [String] = []
        let notifier = RunCompletionNotifier(
            isFrontmost: { false }, post: { _, _, _, id in ids.append(id) })
        _ = notifier.runFinished(title: "X", slug: "00001-a", projectRoot: URL(filePath: "/p"))
        _ = notifier.runFinished(title: "X", slug: "00001-a", projectRoot: URL(filePath: "/p"))
        #expect(ids.count == 2)
        #expect(ids[0] != ids[1])
        #expect(ids.allSatisfy { $0.hasPrefix("run-finished-00001-a-") })
    }
}
