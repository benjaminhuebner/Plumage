import AppKit
// @preconcurrency: SwiftTerm 1.13.0 (swift-tools 5.9) has no Swift 6 Sendable
// annotations. LocalProcess defaults its dispatch queue to DispatchQueue.main,
// so all LocalProcessTerminalViewDelegate callbacks arrive on the main thread —
// the @MainActor Coordinator below is safe. See notes.md #00021-embedded-terminal.
@preconcurrency import SwiftTerm
import SwiftUI

struct EmbeddedTerminalView: NSViewRepresentable {
    let cwd: URL
    let binaryURL: URL

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        applyForeground(to: view)
        context.coordinator.lastColorScheme = colorScheme

        // Shell-wrap so we can set cwd (LocalProcessTerminalView has no direct
        // cwd parameter). exec replaces the shell with claude — only one
        // process boundary remains, and SIGHUP still propagates to claude.
        let quotedPath = cwd.path.replacingOccurrences(of: "'", with: #"'\''"#)
        let claudePath = binaryURL.path.replacingOccurrences(of: "'", with: #"'\''"#)
        view.startProcess(
            executable: "/bin/sh",
            args: ["-c", "cd '\(quotedPath)' && exec '\(claudePath)'"],
            environment: Self.environmentForClaude()
        )
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        guard context.coordinator.lastColorScheme != colorScheme else { return }
        context.coordinator.lastColorScheme = colorScheme
        nsView.nativeBackgroundColor = .clear
        nsView.layer?.backgroundColor = NSColor.clear.cgColor
        applyForeground(to: nsView)
    }

    static func dismantleNSView(
        _ nsView: LocalProcessTerminalView, coordinator: Coordinator
    ) {
        // Without explicit terminate(), LocalProcess.deinit leaves the child
        // running and the PTY fd pair leaked for the app session.
        nsView.terminate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func applyForeground(to view: LocalProcessTerminalView) {
        view.nativeForegroundColor =
            colorScheme == .dark
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(white: 0.15, alpha: 1)
    }

    private static func environmentForClaude() -> [String] {
        // Inherit the parent app's full environment so claude finds the same
        // auth state (~/.claude/.credentials.json, env tokens, keychain access)
        // that the chat-mode subprocess gets. The earlier minimal-allowlist
        // approach left interactive claude unauthenticated even though chat
        // mode worked. Override TERM and augment PATH for a launched-from-
        // Finder Plumage that didn't inherit the user's shell PATH.
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
        var lastColorScheme: ColorScheme?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
