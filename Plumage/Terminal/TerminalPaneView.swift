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
        .onChange(of: modeRaw, initial: false) { oldRaw, newRaw in
            handleModeChange(
                from: TerminalPaneMode(rawValue: oldRaw) ?? .chat,
                to: TerminalPaneMode(rawValue: newRaw) ?? .chat
            )
        }
    }

    private func handleModeChange(from old: TerminalPaneMode, to new: TerminalPaneMode) {
        guard old != new else { return }
        switch new {
        case .terminal:
            // Chat must release the session log before the terminal claude
            // resumes it — handOff terminates the chat subprocess synchronously.
            session.handOff()
        case .chat:
            // Terminal view will be dismantled by SwiftUI (terminate sends
            // SIGHUP to its claude). Respawn chat under the same conversationID
            // so the freshly-rendered ChatView is wired to a live process.
            session.restart()
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Spacer()
            TerminalModeToggle(
                mode: Binding(
                    get: { mode },
                    set: { modeRaw = $0.rawValue }
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
                .id(mode)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: mode)
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
            EmbeddedTerminalView(
                cwd: session.cwd,
                binaryURL: session.binaryURL,
                conversationID: session.conversationID
            )
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
