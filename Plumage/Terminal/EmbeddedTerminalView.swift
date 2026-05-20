import AppKit
// @preconcurrency: SwiftTerm 1.13.0 (swift-tools 5.9) has no Swift 6 Sendable
// annotations. LocalProcess defaults its dispatch queue to DispatchQueue.main,
// so all LocalProcessTerminalViewDelegate callbacks arrive on the main thread —
// the @MainActor Coordinator below is safe. See notes.md #00021-embedded-terminal.
@preconcurrency import SwiftTerm
import SwiftUI

struct EmbeddedTerminalView: View {
    let session: TerminalClaudeSession

    var body: some View {
        ZStack {
            SwiftTermBridge(session: session)

            if showsBootOverlay {
                bootOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsBootOverlay)
    }

    private var showsBootOverlay: Bool {
        if case .starting = session.state { return true }
        return false
    }

    @ViewBuilder
    private var bootOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Resuming session…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

private struct SwiftTermBridge: NSViewRepresentable {
    let session: TerminalClaudeSession

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> PersistentCursorTerminalView {
        let view = PersistentCursorTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        applyForeground(to: view)
        context.coordinator.lastColorScheme = colorScheme

        view.caretViewTracksFocus = false
        view.caretColor = NSColor.labelColor
        view.cursorStyleChanged(source: view.terminal, newStyle: .blinkBlock)

        // Defense in depth: TerminalClaudeSession's shellSpawnArgs already
        // single-quote-escapes ', but precondition on null/newline lives in
        // shellQuotedAttachArgs — bail out early to avoid spawning into a
        // corrupt environment.
        guard TerminalClaudeSession.isShellSafe(session.cwd.path),
            TerminalClaudeSession.isShellSafe(session.binaryURL.path)
        else {
            return view
        }
        let args = session.shellSpawnArgs()
        let env = Self.environmentForClaude()

        view.startProcess(
            executable: "/bin/sh",
            args: args,
            environment: env
        )
        // SwiftTerm's startProcess returns the instant the PTY is wired up,
        // but claude itself spends ~1.6s on hooks / plugins / CLAUDE.md /
        // --resume replay. Holding the session in .starting masks that window
        // with the "Resuming session…" overlay; once we flip to .running the
        // overlay fades and subsequent mode toggles see the session already
        // running so they never re-enter .starting.
        context.coordinator.markStartedTask?.cancel()
        context.coordinator.markStartedTask = Task { @MainActor [weak session] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let session else { return }
            session.markStarted()
        }
        // SwiftTerm starts unfocused inside an NSViewRepresentable. Without
        // a firstResponder hand-off the caret renders as a hollow outline
        // (drawCursor uses TerminalView.hasFocus) and keystrokes can be
        // dropped (notes.md 2026-05-12 #00020-spike entry). Window may
        // still be nil during the first layout pass — the responder hop
        // is best-effort, not load-bearing.
        view.window?.makeFirstResponder(view)
        return view
    }

    func updateNSView(_ nsView: PersistentCursorTerminalView, context: Context) {
        guard context.coordinator.lastColorScheme != colorScheme else { return }
        context.coordinator.lastColorScheme = colorScheme
        nsView.nativeBackgroundColor = .clear
        nsView.layer?.backgroundColor = NSColor.clear.cgColor
        applyForeground(to: nsView)
    }

    @MainActor
    static func dismantleNSView(
        _ nsView: PersistentCursorTerminalView, coordinator: Coordinator
    ) {
        // Without explicit terminate(), LocalProcess.deinit leaves the child
        // running and the PTY fd pair leaked for the app session.
        coordinator.markStartedTask?.cancel()
        coordinator.markStartedTask = nil
        nsView.stopCursorKeepAlive()
        nsView.terminate()
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    private func applyForeground(to view: PersistentCursorTerminalView) {
        view.nativeForegroundColor =
            colorScheme == .dark
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(white: 0.15, alpha: 1)
    }

    private static func environmentForClaude() -> [String] {
        // Inherit the parent app's full environment so claude finds the same
        // auth state (credentials, env tokens, keychain access) that the
        // chat-mode subprocess gets. The earlier minimal-allowlist approach
        // left interactive claude unauthenticated even though chat mode
        // worked. Override TERM and augment PATH for a launched-from-Finder
        // Plumage that didn't inherit the user's shell PATH.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath =
            env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] =
            "\(basePath):/opt/homebrew/bin:\(home)/.local/bin:\(home)/.claude/local"
        return env.map { "\($0.key)=\($0.value)" }
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var session: TerminalClaudeSession?
        var lastColorScheme: ColorScheme?
        var markStartedTask: Task<Void, Never>?

        init(session: TerminalClaudeSession) {
            self.session = session
            super.init()
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            session?.markExited(code: exitCode ?? 0)
        }
    }
}

// claude's interactive REPL sends DECRST 25 (hide cursor) constantly while it
// renders its TUI. SwiftTerm's hide handling lives in two places: the
// delegate callback `hideCursor(source:)`, which we override to a no-op, AND
// the internal flag `Terminal.cursorHidden` which `updateCursorPosition` reads
// every render to decide whether to remove caretView from the hierarchy.
// Plumage can't reach `cursorHidden` directly, but feeding `\e[?25h` (DECSET
// 25 = show cursor) into the terminal parses claude-side and flips the flag
// back to false. A 120 ms repeater wins the race against claude's frequent
// hide commands; the cursor stays continuously visible at the input cell.
final class PersistentCursorTerminalView: LocalProcessTerminalView {
    // nonisolated(unsafe): Timer? is touched from a MainActor-bound start/stop
    // pair and from a nonisolated deinit fallback. SwiftTerm's host normally
    // calls dismantleNSView (which invokes stopCursorKeepAlive) before drop,
    // but the deinit guards against the case where the host short-circuits
    // teardown — Swift 6 rejects a MainActor deinit reading isolated state,
    // hence the unsafe storage. See notes.md #00021-embedded-terminal.
    nonisolated(unsafe) private var cursorKeepAlive: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Timer is started lazily once the view actually enters a window
        // (see viewDidMoveToWindow). Starting in init() ran the 20Hz timer
        // even when the terminal mode wasn't visible.
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        cursorKeepAlive?.invalidate()
        cursorKeepAlive = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startCursorKeepAlive()
        } else {
            stopCursorKeepAlive()
        }
    }

    private func startCursorKeepAlive() {
        cursorKeepAlive?.invalidate()
        // Schedule on .common modes so the timer survives scroll / event
        // tracking on the inspector divider, and pick a fast cadence to win
        // the race against claude's rendering bursts.
        // Timer block is typed @Sendable, but RunLoop.main fires it on the
        // main thread — MainActor.assumeIsolated lets us touch the
        // @MainActor-typed `terminal` property without an extra Task hop per
        // tick. assumeIsolated traps if the assumption is wrong, which it
        // never is for a RunLoop.main-scheduled Timer.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.terminal?.feed(text: "\u{1B}[?25h")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorKeepAlive = timer
    }

    override func hideCursor(source: Terminal) {
        // Intentionally empty — see class comment.
    }

    // Called from SwiftTerm's existing terminate() when the host removes the
    // view, so we don't need to access Timer from a non-isolated deinit (which
    // Swift 6 rejects).
    func stopCursorKeepAlive() {
        cursorKeepAlive?.invalidate()
        cursorKeepAlive = nil
    }
}
