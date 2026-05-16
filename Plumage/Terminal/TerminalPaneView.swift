import SwiftUI

struct TerminalPaneView: View {
    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState

    var body: some View {
        Group {
            switch indicatorState {
            case .loading, .ok:
                ChatView(session: session)
                    .overlay(alignment: .top) {
                        if case .exited(let code, let reason) = session.state {
                            ExitBanner(code: code, reason: reason) {
                                session.restart()
                            }
                        }
                    }
            case .missing, .unsupported, .failed:
                MissingClaudeView(state: indicatorState)
            }
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
