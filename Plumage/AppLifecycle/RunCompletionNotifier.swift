import AppKit
import Foundation
import UserNotifications

// Authorization is requested once; denial degrades to silence (no prompt loop,
// no crash). Posts only while Plumage is backgrounded.
@MainActor
final class RunCompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RunCompletionNotifier()

    private var authorized = false
    private var requested = false

    private let isFrontmost: @MainActor () -> Bool
    private let post: @MainActor (_ title: String, _ slug: String, _ projectRoot: URL) -> Void

    private struct RunWatch {
        let source: FSEventSource
        var liveSlugs: Set<String>
    }
    private var watches: [String: RunWatch] = [:]

    init(
        isFrontmost: @escaping @MainActor () -> Bool = { NSApp.isActive },
        post: (@MainActor (String, String, URL) -> Void)? = nil
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
        post(title, slug, projectRoot)
        return true
    }

    private static func postBanner(title: String, slug: String, projectRoot: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Issue \(title)"
        content.body = "Run finished — waiting for review"
        content.userInfo = ["projectRoot": projectRoot.path]
        let request = UNNotificationRequest(
            identifier: "run-finished-\(slug)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // FSEvents (unlike the inactive-gated kanban) keeps firing while backgrounded,
    // so a run-state file vanishing is the finish signal even with no window focus.
    func watchProjectRuns(root: URL) {
        let key = root.standardizedFileURL.path
        guard watches[key] == nil, let bundle = try? BundleResolver.findBundle(in: root) else { return }
        let runsDir = bundle.appendingPathComponent("runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        let source = FSEventSource(directory: runsDir) { [weak self] in
            Task { @MainActor in self?.checkFinished(root: root) }
        }
        source.start()
        watches[key] = RunWatch(source: source, liveSlugs: Self.currentLiveSlugs(root: root))
    }

    func unwatchProjectRuns(root: URL) {
        let key = root.standardizedFileURL.path
        watches[key]?.source.stop()
        watches[key] = nil
    }

    nonisolated static func finishedSlugs(was: Set<String>, now: Set<String>) -> Set<String> {
        was.subtracting(now)
    }

    private static func currentLiveSlugs(root: URL) -> Set<String> {
        ImplementRunScanner.liveImplementRun(in: root).map { [$0.issue] } ?? []
    }

    private func checkFinished(root: URL) {
        let key = root.standardizedFileURL.path
        guard var watch = watches[key] else { return }
        let now = Self.currentLiveSlugs(root: root)
        let finished = Self.finishedSlugs(was: watch.liveSlugs, now: now)
        watch.liveSlugs = now
        watches[key] = watch
        for slug in finished {
            runFinished(
                title: Self.issueTitle(root: root, slug: slug) ?? slug, slug: slug, projectRoot: root)
        }
    }

    private static func issueTitle(root: URL, slug: String) -> String? {
        let specURL = root.appendingPathComponent(".claude/issues/\(slug)/spec.md")
        guard let content = try? String(contentsOf: specURL, encoding: .utf8) else { return nil }
        return (try? SpecParser.parse(content: content, folderName: slug).get())?.title
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
