import Foundation
import Observation

@Observable
@MainActor
final class TerminalClaudeSession {
    enum State: Sendable, Equatable {
        case idle
        case starting(cwd: URL)
        case running
        case exited(code: Int32, reason: ClaudeSession.ExitReason)
    }

    let cwd: URL
    let binaryURL: URL
    private let sessionIDStoreURL: URL
    private let sessionLogRoot: URL
    // Returns conversation IDs that must NOT be adopted by reconcile —
    // primarily the chat session's ID, since chat shares the same log dir.
    // ProjectWindow injects a closure with weak-capture on the chat session
    // so the lookup stays live; tests use the default empty set. Mutable so
    // ProjectWindow can re-wire after `rebuilt(for:replacing:)` swaps in a
    // fresh chat session instance whose weak ref would otherwise be stale.
    private var excludedSessionIDs: () -> Set<String>

    private(set) var state: State = .idle
    private(set) var conversationID: String
    // Wall-clock cutoff used by reconcileSessionFromDisk to reject log files
    // that pre-date this session boot. Set on markStarted(), cleared on stop().
    private var launchInstant: Date?
    // FSEvents watcher on the claude log dir. Owned by the session so its
    // lifetime matches the running subprocess. Nil while .idle/.exited.
    private var logWatcher: SessionLogWatcher?
    // Inject buffer drained by SwiftTermBridge once state == .running.
    // Producers (workflow buttons) call enqueue() unconditionally; the bridge
    // observes mutations via @Observable and flushes through send(txt:).
    // Cleared with consumePending() at the start of every fresh inject so
    // stale entries from a prior failed flush don't ride along.
    private(set) var pendingInput: [String] = []
    // Bumped by restart() so EmbeddedTerminalView can use it as a SwiftUI .id
    // and force SwiftTermBridge to dismantle + remount, which respawns the
    // PTY-owned claude subprocess. State alone can't drive a remount because
    // the bridge persists across inspector toggles (SwiftUI's .inspector
    // hides its column without removing content from the view tree).
    private(set) var restartEpoch: Int = 0
    // Synchronously kill the PTY subprocess on stop(). Registered by
    // SwiftTermBridge.makeNSView so window-close → onDisappear → stop()
    // terminates the child without relying on SwiftUI's view-tree teardown
    // timing. The real Process lives in SwiftTerm, not in this class.
    private var stopHandler: (() -> Void)?

    init(
        cwd: URL,
        binaryURL: URL,
        sessionIDStoreOverride: URL? = nil,
        sessionLogRoot: URL? = nil,
        excludedSessionIDs: @escaping () -> Set<String> = { [] }
    ) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.sessionIDStoreURL =
            sessionIDStoreOverride
            ?? cwd
            .appendingPathComponent(".plumage", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("terminal-id")
        self.sessionLogRoot =
            sessionLogRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        self.excludedSessionIDs = excludedSessionIDs

        if let persisted = Self.loadPersistedID(from: self.sessionIDStoreURL) {
            self.conversationID = persisted
        } else {
            let fresh = UUID().uuidString.lowercased()
            self.conversationID = fresh
            Self.persistID(fresh, to: self.sessionIDStoreURL)
        }
    }

    static func rebuilt(
        for handleURL: URL, replacing prior: TerminalClaudeSession
    ) -> TerminalClaudeSession {
        if prior.cwd == handleURL { return prior }
        prior.stop()
        let binary =
            (try? ProductionProcessRunner.locateBinary())
            ?? URL(filePath: "/dev/null")
        return TerminalClaudeSession(cwd: handleURL, binaryURL: binary)
    }

    func attach() {
        switch state {
        case .idle, .exited:
            state = .starting(cwd: cwd)
        case .starting, .running:
            break
        }
    }

    func markStarted() {
        if case .starting = state {
            state = .running
            launchInstant = Date()
            startLogWatcher()
            // Initial reconcile in case a rotation happened before the
            // watcher armed (or in case claude wrote the post-/clear file
            // during the same wall-clock second markStarted fires).
            reconcileSessionFromDisk()
        }
    }

    func markExited(code: Int32) {
        switch state {
        case .idle, .exited:
            return
        case .starting, .running:
            stopLogWatcher()
            state = .exited(code: code, reason: Self.classify(code))
        }
    }

    func stop() {
        switch state {
        case .starting, .running:
            // Last-chance reconcile before tearing the watcher down — covers
            // the race where claude rotated the log right before stop() but
            // the FSEvent didn't get delivered.
            reconcileSessionFromDisk()
            stopLogWatcher()
            // Kill the PTY-owned subprocess synchronously before flipping
            // state. SwiftTermBridge.dismantleNSView is the fallback path,
            // but it's only guaranteed to fire after the view leaves the
            // hierarchy — which during window-close races onDisappear. Calling
            // stopHandler here closes that race.
            stopHandler?()
            state = .exited(code: 0, reason: .userClosed)
        case .idle, .exited:
            return
        }
    }

    // Mid-Lifecycle restart for the ExitBanner: flip state back to .starting
    // and bump restartEpoch so SwiftTermBridge re-mounts and spawns a fresh
    // claude. Only valid from .exited — banner is the only caller.
    func restart() {
        guard case .exited = state else { return }
        state = .starting(cwd: cwd)
        restartEpoch &+= 1
    }

    func enqueue(_ text: String) {
        pendingInput.append(text)
    }

    func consumePending() -> [String] {
        defer { pendingInput.removeAll() }
        return pendingInput
    }

    func registerStopHandler(_ handler: @escaping () -> Void) {
        stopHandler = handler
    }

    func setExcludedSessionIDs(_ provider: @escaping () -> Set<String>) {
        excludedSessionIDs = provider
    }

    func clearStopHandler() {
        stopHandler = nil
    }

    func resumeOrInitArgs() -> [String] {
        guard sessionLogExists() else {
            return ["--session-id", conversationID]
        }
        return ["--resume", conversationID]
    }

    // /bin/sh -c "cd '<cwd>' && exec '<claude>' [--session-id|--resume '<uuid>']"
    func shellSpawnArgs() -> [String] {
        let quotedCwd = cwd.path.replacingOccurrences(of: "'", with: #"'\''"#)
        let quotedBin = binaryURL.path.replacingOccurrences(of: "'", with: #"'\''"#)
        let attach = Self.shellQuotedAttachArgs(resumeOrInitArgs())
        return ["-c", "cd '\(quotedCwd)' && exec '\(quotedBin)' \(attach)"]
    }

    static func shellQuotedAttachArgs(_ args: [String]) -> String {
        args.map { arg in
            precondition(isShellSafe(arg), "shellQuotedAttachArgs: unsafe arg")
            let escaped = arg.replacingOccurrences(of: "'", with: #"'\''"#)
            return "'\(escaped)'"
        }
        .joined(separator: " ")
    }

    static func isShellSafe(_ value: String) -> Bool {
        !value.contains("\0") && !value.contains("\n") && !value.contains("\r")
    }

    private func sessionLogExists() -> Bool {
        FileManager.default.fileExists(atPath: sessionLogURL().path)
    }

    private func sessionLogURL() -> URL {
        sessionLogDirectory()
            .appendingPathComponent("\(conversationID).jsonl")
    }

    private func sessionLogDirectory() -> URL {
        let encoded = cwd.path.replacingOccurrences(of: "/", with: "-")
        return sessionLogRoot.appendingPathComponent(encoded)
    }

    private func startLogWatcher() {
        guard logWatcher == nil else { return }
        let watcher = SessionLogWatcher(directory: sessionLogDirectory()) { [weak self] in
            // FSEvents callback fires on the watcher's own dispatch queue;
            // hop to MainActor before touching @Observable state.
            Task { @MainActor [weak self] in
                self?.reconcileSessionFromDisk()
            }
        }
        watcher.start()
        logWatcher = watcher
    }

    private func stopLogWatcher() {
        logWatcher?.stop()
        logWatcher = nil
        launchInstant = nil
    }

    // Scans the claude log directory for a `.jsonl` whose mtime is at or
    // after `launchInstant` and whose name is neither the current
    // conversationID nor in `excludedSessionIDs()`. The first match is
    // adopted as the new conversationID and persisted, so an app-restart
    // resumes the post-/clear session instead of the pre-/clear one.
    func reconcileSessionFromDisk() {
        guard let launchInstant else { return }
        let dir = sessionLogDirectory()
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return }
        let excluded = excludedSessionIDs()
        var bestID: String?
        var bestMTime: Date?
        for entry in entries where entry.pathExtension == "jsonl" {
            let id = entry.deletingPathExtension().lastPathComponent
            if id == conversationID { continue }
            if excluded.contains(id) { continue }
            guard
                let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey]),
                let mtime = values.contentModificationDate,
                mtime >= launchInstant
            else { continue }
            if let current = bestMTime, mtime <= current { continue }
            bestMTime = mtime
            bestID = id
        }
        guard let bestID else { return }
        conversationID = bestID
        Self.persistID(bestID, to: sessionIDStoreURL)
    }

    private nonisolated static func loadPersistedID(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return raw
    }

    private nonisolated static func persistID(_ id: String, to url: URL) {
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        try? id.write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated static func classify(_ code: Int32) -> ClaudeSession.ExitReason {
        switch code {
        case 0: return .userClosed
        case 128...159: return .killed
        default: return .crashed
        }
    }
}
