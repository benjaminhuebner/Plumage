import AppKit
import Foundation
import UserNotifications
import os

// Authorization is requested once; denial degrades to silence (no prompt loop,
// no crash). Posts only while Plumage is backgrounded.
@MainActor
final class RunCompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RunCompletionNotifier()

    private static let logger = Logger(subsystem: "com.plumage", category: "RunCompletionNotifier")

    private var authorized = false
    private var requested = false
    private var postSeq: UInt64 = 0

    private let isFrontmost: @MainActor () -> Bool
    private let post: @MainActor (_ title: String, _ slug: String, _ projectRoot: URL, _ identifier: String) -> Void

    private struct RunWatch {
        var sources: [FSEventSource]
        var worktreeRoots: [URL]
        var liveSlugs: Set<String>
    }
    private var watches: [String: RunWatch] = [:]

    init(
        isFrontmost: @escaping @MainActor () -> Bool = { NSApp.isActive },
        post: (@MainActor (String, String, URL, String) -> Void)? = nil
    ) {
        self.isFrontmost = isFrontmost
        if let post {
            self.post = post
            self.authorized = true
        } else {
            self.post = RunCompletionNotifier.postBanner
        }
        super.init()
    }

    func activate() {
        UNUserNotificationCenter.current().delegate = self
        guard !requested else { return }
        requested = true
        // Request only .alert: the banner sets no sound, and requesting .sound
        // makes `granted` false for an alert-only grant — silently gating banners off.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) {
            [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    nonisolated static func shouldPost(isFrontmost: Bool, authorized: Bool) -> Bool {
        authorized && !isFrontmost
    }

    @discardableResult
    func runFinished(title: String, slug: String, projectRoot: URL) -> Bool {
        guard Self.shouldPost(isFrontmost: isFrontmost(), authorized: authorized) else { return false }
        // A repeated identifier silently replaces the prior banner in
        // UNUserNotificationCenter, so a second run of the slug needs a fresh one.
        postSeq &+= 1
        post(title, slug, projectRoot, "run-finished-\(slug)-\(postSeq)")
        return true
    }

    private static func postBanner(title: String, slug: String, projectRoot: URL, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = "Issue \(title)"
        content.body = "Run finished — waiting for review"
        content.userInfo = ["projectRoot": projectRoot.path]
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // FSEvents (unlike the inactive-gated kanban) keeps firing while backgrounded,
    // so a run-state file vanishing is the finish signal even with no window focus.
    func watchProjectRuns(root: URL) {
        let key = root.standardizedFileURL.path
        guard watches[key] == nil else { return }
        guard let bundle = try? BundleResolver.findBundle(in: root) else {
            Self.logger.warning(
                "no bundle at \(root.path, privacy: .public) — run notifications off for this project")
            return
        }
        let source = Self.makeSource(forRunsIn: bundle, root: root, owner: self)
        watches[key] = RunWatch(
            sources: [source], worktreeRoots: [root],
            liveSlugs: Self.currentLiveSlugs(roots: [root]))
        // Worktree runs write to a separate bundle copy the primary runs dir
        // never sees; the git enumeration is kept off the FSEvent hot path.
        Task { @MainActor [weak self] in await self?.expandWorktreeWatches(root: root, key: key) }
    }

    func unwatchProjectRuns(root: URL) {
        let key = root.standardizedFileURL.path
        watches[key]?.sources.forEach { $0.stop() }
        watches[key] = nil
    }

    private static func makeSource(
        forRunsIn bundle: URL, root: URL, owner: RunCompletionNotifier
    )
        -> FSEventSource
    {
        let runsDir = bundle.appendingPathComponent("runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        let source = FSEventSource(directory: runsDir) { [weak owner] in
            Task { @MainActor in owner?.checkFinished(root: root) }
        }
        source.start()
        return source
    }

    private func expandWorktreeWatches(root: URL, key: String) async {
        let roots = await Self.worktreeRoots(root: root)
        let primaryKey = root.standardizedFileURL.path
        var added: [FSEventSource] = []
        for worktree in roots where worktree.standardizedFileURL.path != primaryKey {
            guard let bundle = try? BundleResolver.findBundle(in: worktree) else { continue }
            added.append(Self.makeSource(forRunsIn: bundle, root: worktree, owner: self))
        }
        guard watches[key] != nil else {
            added.forEach { $0.stop() }
            return
        }
        watches[key]?.sources.append(contentsOf: added)
        watches[key]?.worktreeRoots = roots
        watches[key]?.liveSlugs = Self.currentLiveSlugs(roots: roots)
    }

    nonisolated static func finishedSlugs(was: Set<String>, now: Set<String>) -> Set<String> {
        was.subtracting(now)
    }

    private static func worktreeRoots(root: URL) async -> [URL] {
        let worktrees = (try? await GitWorktreeLister().worktrees(repoURL: root)) ?? []
        return worktrees.isEmpty ? [root] : worktrees.map(\.path)
    }

    private static func currentLiveSlugs(roots: [URL]) -> Set<String> {
        Set(ImplementRunScanner.liveImplementRuns(acrossWorktreeRoots: roots).map { $0.run.issue })
    }

    private func checkFinished(root: URL) {
        let key = root.standardizedFileURL.path
        guard let watch = watches[key] else { return }
        let now = Self.currentLiveSlugs(roots: watch.worktreeRoots)
        let finished = Self.finishedSlugs(was: watch.liveSlugs, now: now)
        watches[key]?.liveSlugs = now
        for slug in finished {
            Task { @MainActor [weak self] in
                let title = await Self.issueTitle(root: root, slug: slug) ?? slug
                self?.runFinished(title: title, slug: slug, projectRoot: root)
            }
        }
    }

    private static func issueTitle(root: URL, slug: String) async -> String? {
        await Task.detached { () -> String? in
            let specURL = root.appendingPathComponent(".claude/issues/\(slug)/spec.md")
            guard let content = try? String(contentsOf: specURL, encoding: .utf8) else { return nil }
            return (try? SpecParser.parse(content: content, folderName: slug).get())?.title
        }.value
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rootPath = response.notification.request.content.userInfo["projectRoot"] as? String
        completionHandler()
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            // Best-effort: open/focus the project; a removed target just no-ops.
            if let rootPath, let bundle = try? BundleResolver.findBundle(in: URL(filePath: rootPath)) {
                NSWorkspace.shared.open(bundle)
            }
        }
    }
}
