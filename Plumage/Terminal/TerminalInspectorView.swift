import SwiftUI

struct TerminalInspectorView: View {
    let session: TerminalClaudeSession

    var body: some View {
        EmbeddedTerminalView(session: session)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay(alignment: .top) {
                if case .exited(let code, let reason) = session.state {
                    ExitBanner(code: code, reason: reason) {
                        session.restart()
                    }
                }
            }
            // .id(cwd) forces SwiftUI to rebuild the bridge (and its
            // Coordinator) when ProjectWindow swaps the session for a
            // different handle.url — otherwise the Coordinator's `weak
            // session` keeps pointing at the prior TerminalClaudeSession.
            .id(session.cwd)
    }
}

#Preview {
    let session = TerminalClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true")
    )
    return TerminalInspectorView(session: session)
        .frame(width: 480, height: 600)
}
