#if DEBUG
import AppKit
import SwiftUI
// @preconcurrency: SwiftTerm 1.13.0 (swift-tools 5.9) has no Swift 6 Sendable
// annotations. LocalProcess defaults its dispatch queue to DispatchQueue.main,
// so all LocalProcessTerminalViewDelegate callbacks arrive on the main thread —
// the @MainActor Coordinator below is safe. See notes.md #00020-swiftterm-spike.
@preconcurrency import SwiftTerm

struct SwiftTermHostingView: NSViewRepresentable {
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
        // Launches the user's shell in a PTY; LocalProcess pumps output on
        // DispatchQueue.main. Env is a minimal allowlist — the parent process
        // env carries developer secrets (API keys, tokens) that should not
        // flow into a Plumage-spawned shell, even in DEBUG.
        view.startProcess(
            executable: Self.shellExecutable(),
            args: ["-l"],
            environment: Self.minimalEnvironment()
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

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        // LocalProcess.deinit does not terminate the child — without this
        // SIGTERM the zsh process, PTY fd pair, and DispatchIO read loop leak
        // for the app session.
        nsView.terminate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func applyForeground(to view: LocalProcessTerminalView) {
        view.nativeForegroundColor =
            colorScheme == .dark
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(white: 0.15, alpha: 1)
    }

    private static func shellExecutable() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
            !shell.isEmpty,
            FileManager.default.isExecutableFile(atPath: shell)
        {
            return shell
        }
        return "/bin/zsh"
    }

    private static func minimalEnvironment() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lang = "\(Locale.current.identifier).UTF-8"
        return [
            "TERM=xterm-256color",
            "LANG=\(lang)",
            "HOME=\(home)",
            "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ]
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
#endif
