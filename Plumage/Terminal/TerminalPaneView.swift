import SwiftUI

enum TerminalPaneMode: String, CaseIterable, Sendable {
    case chat
    case terminal
}

struct TerminalPaneView: View {
    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState

    @SceneStorage("terminalPaneMode") private var modeRaw: String =
        TerminalPaneMode.chat.rawValue

    private var mode: TerminalPaneMode {
        TerminalPaneMode(rawValue: modeRaw) ?? .chat
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
    }

    private func performModeChange(to target: TerminalPaneMode) {
        let current = mode
        guard current != target else { return }
        // Mark handoff pending BEFORE modeRaw mutates and triggers the body
        // re-eval that mounts/dismantles SwiftTermBridge. Without this, the
        // new mode's spawn Task races the .onChange that would otherwise call
        // handOff: it sees handOffPending=false and starts claude immediately,
        // then claude prints "Session ID … is already in use" because the
        // previous claude hasn't released the log lock yet.
        session.markHandOffStarting()
        switch target {
        case .terminal:
            // handOff replaces the chat process's terminationHandler so
            // handOffPending flips to false once chat-claude is actually dead.
            session.handOff()
        case .chat:
            // SwiftUI will dismantle SwiftTermBridge as part of the body
            // re-eval; the bridge's dismantleNSView/processTerminated path
            // flips handOffPending to false when terminal-claude exits.
            // resumeAfterHandOff already awaits that signal before spawning.
            session.resumeAfterHandOff()
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Spacer()
            TerminalModeToggle(
                mode: Binding(
                    get: { mode },
                    set: { newMode in
                        performModeChange(to: newMode)
                        modeRaw = newMode.rawValue
                    }
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch indicatorState {
        case .loading, .ok:
            modeContent
                .id(modeRaw)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: modeRaw)
        case .missing, .unsupported, .failed:
            MissingClaudeView(state: indicatorState)
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .chat:
            ChatView(session: session)
                .overlay(alignment: .top) {
                    if case .exited(let code, let reason) = session.state {
                        ExitBanner(code: code, reason: reason) {
                            session.restart()
                        }
                    }
                }
        case .terminal:
            EmbeddedTerminalView(session: session)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }
}

#Preview("Running") {
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        autoSpawn: false
    )
    session.start()
    session.handleEvent(.systemInit(sessionID: "preview"))
    session.handleEvent(.assistant([.text("Hi there.")]))
    return TerminalPaneView(session: session, indicatorState: .loading)
        .frame(width: 460, height: 600)
}

#Preview("Exited (crashed)") {
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        autoSpawn: false
    )
    session.start()
    session.handleEvent(.systemInit(sessionID: "preview"))
    session.handleExit(code: 1)
    return TerminalPaneView(session: session, indicatorState: .loading)
        .frame(width: 460, height: 600)
}

#Preview("Missing") {
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        autoSpawn: false
    )
    return TerminalPaneView(session: session, indicatorState: .missing)
        .frame(width: 460, height: 600)
}
