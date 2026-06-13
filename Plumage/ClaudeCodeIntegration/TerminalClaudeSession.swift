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
    let modelChoice: ModelChoice
    let effortChoice: EffortLevel
    // nil disables disk persistence — additional tabs pass persistConversationID:
    // false so each gets a fresh UUID without touching the on-disk pointer. When a
    // tab does persist, the store lives under the bundle's `sessions/`, mirroring ClaudeSession.
    private let sessionIDStoreURL: URL?
    private let sessionLogRoot: URL
    // Conversation IDs reconcile must NOT adopt — primarily the chat session's,
    // since chat shares the same log dir. Mutable so ProjectWindow can re-wire after
    // `rebuilt(for:replacing:)` swaps in a fresh chat session (stale weak ref otherwise).
    private var excludedSessionIDs: @MainActor () -> Set<String>
    // nil means no --permission-mode flag is appended; the workflow-tab path
    // sets one of plan/acceptEdits/default so claude boots with the right
    // permission policy without a follow-up TTY toggle.
    private let permissionMode: PermissionMode?

    private(set) var state: State = .idle
    private(set) var conversationID: String
    // Wall-clock cutoff used by reconcileSessionFromDisk to reject log files
    // that pre-date this session boot. Set on markStarted(), cleared on stop().
    private var launchInstant: Date?
    // FSEvents watcher on the claude log dir. Owned by the session so its
    // lifetime matches the running subprocess. Nil while .idle/.exited.
    private var logWatcher: SessionLogWatcher?
    // Inject buffer drained by SwiftTermBridge once state == .running (observed
    // via @Observable, flushed through send(txt:)). consumePending() clears it at
    // every fresh inject so stale entries from a prior failed flush don't ride along.
    private(set) var pendingInput: [String] = []
    // Bumped by restart(); EmbeddedTerminalView uses it as a SwiftUI .id to force
    // SwiftTermBridge to dismantle + remount, respawning the PTY claude. State alone
    // can't drive a remount — .inspector hides its column without unmounting content.
    private(set) var restartEpoch: Int = 0
    // Synchronously kills the PTY subprocess on stop(); registered by
    // SwiftTermBridge.makeNSView so window-close terminates the child without relying
    // on SwiftUI's teardown timing. The real Process lives in SwiftTerm, not here.
    private var stopHandler: (() -> Void)?

    init(
        cwd: URL,
        binaryURL: URL,
        stateDirectory: URL? = nil,
        modelChoice: ModelChoice = .default,
        effortChoice: EffortLevel = .default,
        sessionIDStoreOverride: URL? = nil,
        sessionLogRoot: URL? = nil,
        excludedSessionIDs: @escaping @MainActor () -> Set<String> = { [] },
        persistConversationID: Bool = true,
        permissionMode: PermissionMode? = nil
    ) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.modelChoice = modelChoice
        self.effortChoice = effortChoice
        self.permissionMode = permissionMode
        if persistConversationID {
            let resolved =
                sessionIDStoreOverride
                ?? stateDirectory?
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent("terminal-id")
            assert(
                resolved != nil,
                "persistConversationID requires stateDirectory or sessionIDStoreOverride; "
                    + "persistence is silently disabled otherwise")
            self.sessionIDStoreURL = resolved
        } else {
            self.sessionIDStoreURL = nil
        }
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

    // isolated deinit (Swift 6.2) safety net: primary teardown is stop()/markExited(),
    // but an abnormal window close can skip those — the SessionLogWatcher and the
    // stopHandler closure (retains the PTY view) would leak without this.
    isolated deinit {
        stopLogWatcher()
        stopHandler = nil
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
            // Kill the PTY subprocess synchronously before flipping state.
            // SwiftTermBridge.dismantleNSView only fires after the view leaves
            // the hierarchy — which races onDisappear during window-close.
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

    enum InjectResult: Sendable, Equatable {
        case injected
        case sessionExited
        case timedOut
        case cancelled
    }

    // The submit \r must be its OWN entry, never appended to the body: claude's
    // paste heuristic treats body + trailing \r in one read() burst as pasted content
    // and swallows the \r. The pre-submit gap scales with the payload so the body clears first.
    func injectCommands(
        _ lines: [String],
        timeout: Duration = .seconds(5),
        // Test seams: the gap floors at 800 ms, so without an override every
        // injectCommands test pays a real ~second of sleep; the injectable
        // clock lets a ManualClock test pin the bodyDelay>0 path itself.
        bodyDelay: Duration? = nil,
        clock: any Clock<Duration> = ContinuousClock()
    ) async -> InjectResult {
        let payloads = lines.flatMap { line -> [String] in
            [line.replacingOccurrences(of: "\r", with: ""), "\r"]
        }
        return await injectLines(
            payloads, timeout: timeout,
            bodyDelay: bodyDelay ?? Self.injectBodyDelay(for: payloads),
            clock: clock)
    }

    // Single wait-for-running gate up front, `bodyDelay` between enqueues.
    // consumePending() runs exactly ONCE at entry — per-line consumption would
    // race the terminal view's pendingInput drain and silently drop a prior line.
    private func injectLines(
        _ lines: [String],
        timeout: Duration = .seconds(5),
        bodyDelay: Duration = TerminalClaudeSession.injectBodyDelayFloor,
        clock: any Clock<Duration> = ContinuousClock()
    ) async -> InjectResult {
        guard !lines.isEmpty else { return .injected }
        _ = consumePending()

        let deadline = ContinuousClock.now + timeout
        while !isRunningState(state), ContinuousClock.now < deadline {
            if Task.isCancelled { return .cancelled }
            if case .exited = state { return .sessionExited }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if Task.isCancelled { return .cancelled }
        guard isRunningState(state) else { return .timedOut }

        for (index, line) in lines.enumerated() {
            if index > 0 {
                try? await clock.sleep(for: bodyDelay)
                if Task.isCancelled { return .cancelled }
                if case .exited = state { return .sessionExited }
            }
            enqueue(line)
        }
        return .injected
    }

    private nonisolated func isRunningState(_ state: State) -> Bool {
        if case .running = state { return true }
        return false
    }

    // Gap between injected body and submit \r: if the \r lands in the same read()
    // burst as the body's tail, claude's paste heuristic eats it and nothing submits.
    // Scales with the largest payload (≈125 KB/s); 800 ms floor, 64 KB cap bounds ≈8 s.
    nonisolated static let injectBodyDelayFloor: Duration = .milliseconds(800)
    nonisolated static func injectBodyDelay(for payloads: [String]) -> Duration {
        let maxBytes = payloads.map(\.utf8.count).max() ?? 0
        return injectBodyDelayFloor + .milliseconds(maxBytes / 8)
    }

    func registerStopHandler(_ handler: @escaping () -> Void) {
        stopHandler = handler
    }

    func setExcludedSessionIDs(_ provider: @escaping @MainActor () -> Set<String>) {
        excludedSessionIDs = provider
    }

    // Test-visible accessor: the closure itself stays private (re-bound by
    // TerminalTabsModel during tab life-cycle changes), so callers can only
    // observe its result, not swap it.
    func currentExcludedSessionIDs() -> Set<String> {
        excludedSessionIDs()
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

    // /bin/sh -c "cd '<cwd>' && exec '<claude>' --settings '<json>' [--session-id|--resume '<uuid>'] [--permission-mode <mode>] [--model <alias>]"
    func shellSpawnArgs(appearanceIsDark: Bool = true) -> [String] {
        // Per-session theme via --settings — writing the user's global
        // ~/.claude/settings.json re-skinned their own claude terminal. Dark/light follows
        // the view's colorScheme; the JSON has no single quotes, so shellQuote wraps it safely.
        var args = [
            "--settings", ClaudeThemeInstaller.perSessionSettingsJSON(dark: appearanceIsDark),
        ]
        args += resumeOrInitArgs()
        if let permissionMode {
            args += ["--permission-mode", permissionMode.rawCLIValue]
        }
        args += modelChoice.cliArg
        args += effortChoice.cliArg
        // cwd, binary, and every attach arg go through the SAME validated quoting —
        // no value enters the `/bin/sh -c` string without an isShellSafe check, so
        // validation isn't split between here and the call site.
        let quotedCwd = Self.shellQuote(cwd.path)
        let quotedBin = Self.shellQuote(binaryURL.path)
        let attach = Self.shellQuotedAttachArgs(args)
        return ["-c", "cd \(quotedCwd) && exec \(quotedBin) \(attach)"]
    }

    // Inherit the parent app's full environment — a minimal allowlist left
    // interactive claude unauthenticated even though chat mode worked. Override TERM
    // and augment PATH for a Finder-launched Plumage without the user's shell PATH.
    static func spawnEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath =
            env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] =
            "\(basePath):/opt/homebrew/bin:\(home)/.local/bin:\(home)/.claude/local"
        return env.map { "\($0.key)=\($0.value)" }
    }

    static func shellQuotedAttachArgs(_ args: [String]) -> String {
        args.map(shellQuote).joined(separator: " ")
    }

    // Single-quote-wraps a value for POSIX sh. Fail-closed precondition: fires on
    // the three chars single-quoting cannot neutralize (\0, \n, \r) — crashing beats
    // emitting an injectable shell string. Guards against a future user-controlled arg.
    static func shellQuote(_ value: String) -> String {
        precondition(isShellSafe(value), "shellQuote: unsafe arg")
        let escaped = value.replacingOccurrences(of: "'", with: #"'\''"#)
        return "'\(escaped)'"
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
        // Ephemeral sessions opt out of reconcile, so the watcher would just fan
        // out FSEvents into MainActor hops that bail at reconcile's guard. With
        // many open tabs the wasted hops add up; skip the watcher entirely.
        guard sessionIDStoreURL != nil else { return }
        let watcher = SessionLogWatcher(directory: sessionLogDirectory()) { [weak self] in
            // FSEvents fires on the watcher's queue; hop to MainActor before
            // touching @Observable state. The async variant keeps the directory
            // scan off the MainActor — this fires repeatedly while claude streams.
            Task { @MainActor [weak self] in
                await self?.reconcileSessionFromDiskAsync()
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

    // Adopts and persists the first `.jsonl` in the log dir with mtime >=
    // `launchInstant` that is neither the current conversationID nor excluded —
    // so an app-restart resumes the post-/clear session, not the pre-/clear one.
    func reconcileSessionFromDisk() {
        // Ephemeral sessions opt out entirely: without persistence, /clear-rotation
        // tracking has nowhere to write its result, leaving only cross-session
        // adoption — exactly what callers explicitly asked to avoid.
        guard sessionIDStoreURL != nil else { return }
        guard let launchInstant else { return }
        let bestID = Self.scanAdoptableSession(
            in: sessionLogDirectory(),
            currentID: conversationID,
            excluded: excludedSessionIDs(),
            since: launchInstant
        )
        guard let bestID else { return }
        conversationID = bestID
        Self.persistID(bestID, to: sessionIDStoreURL)
    }

    // FSEvents hot-path variant: the scan (N stat calls) runs detached so
    // streaming-log bursts don't pile sync disk I/O onto the MainActor.
    // stop()/markStarted() keep the sync version — must complete before teardown.
    func reconcileSessionFromDiskAsync() async {
        guard sessionIDStoreURL != nil else { return }
        guard let launchInstant else { return }
        let dir = sessionLogDirectory()
        let currentID = conversationID
        let excluded = excludedSessionIDs()
        let bestID = await Task.detached(priority: .utility) {
            Self.scanAdoptableSession(
                in: dir, currentID: currentID, excluded: excluded, since: launchInstant)
        }.value
        // Re-check after the await: a /clear or stop() may have rotated or
        // torn down the session while the scan ran.
        guard let bestID, bestID != conversationID, self.launchInstant != nil else { return }
        conversationID = bestID
        Self.persistID(bestID, to: sessionIDStoreURL)
    }

    private nonisolated static func scanAdoptableSession(
        in dir: URL, currentID: String, excluded: Set<String>, since launchInstant: Date
    ) -> String? {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return nil }
        var bestID: String?
        var bestMTime: Date?
        for entry in entries where entry.pathExtension == "jsonl" {
            let id = entry.deletingPathExtension().lastPathComponent
            if id == currentID { continue }
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
        return bestID
    }

    private nonisolated static func loadPersistedID(from url: URL?) -> String? {
        guard let url,
            let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return raw
    }

    private nonisolated static func persistID(_ id: String, to url: URL?) {
        guard let url else { return }
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
