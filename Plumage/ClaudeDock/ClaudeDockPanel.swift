import SwiftUI

struct ClaudeDockPanel: View {
    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    @Binding var isOpen: Bool

    @SceneStorage("terminalPaneMode") private var modeRaw: String =
        TerminalPaneMode.chat.rawValue

    private var mode: TerminalPaneMode {
        TerminalPaneMode(rawValue: modeRaw) ?? .chat
    }

    var body: some View {
        VStack(spacing: 0) {
            DockPanelHeader(mode: modeBinding, onClose: close)
            content
        }
        .frame(width: 420, height: 560)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .focusable()
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    private func close() {
        isOpen = false
    }

    let sceneStorageKeyForTesting = "terminalPaneMode"
    let defaultModeForTesting: TerminalPaneMode = .chat

    func closeForTesting() { close() }

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
            session.handOff()
        case .chat:
            session.resumeAfterHandOff()
        }
    }

    private var modeBinding: Binding<TerminalPaneMode> {
        Binding(
            get: { mode },
            set: { newMode in
                performModeChange(to: newMode)
                modeRaw = newMode.rawValue
            }
        )
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

private struct DockPanelHeader: View {
    @Binding var mode: TerminalPaneMode
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TerminalModeToggle(mode: $mode)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Claude schließen")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

#Preview("Loading") {
    @Previewable @State var open = true
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        autoSpawn: false
    )
    return ClaudeDockPanel(
        session: session,
        indicatorState: .loading,
        isOpen: $open
    )
    .padding(40)
}
