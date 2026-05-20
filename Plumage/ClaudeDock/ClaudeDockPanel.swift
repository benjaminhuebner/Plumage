import SwiftUI

struct ClaudeDockPanel: View {
    static let sceneStorageKey = "terminalPaneMode"
    static let defaultMode: TerminalPaneMode = .chat
    static let preferredWidth: CGFloat = 420
    static let preferredHeight: CGFloat = 560

    let session: ClaudeSession
    let terminalSession: TerminalClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    @Binding var isOpen: Bool
    // The overlay measures available window height and passes it down so
    // the panel can shrink instead of overflowing the window's top edge
    // when the user resizes near the project window's minHeight (560pt).
    // Defaults to preferredHeight so previews / standalone uses keep
    // their original size.
    var availableHeight: CGFloat = ClaudeDockPanel.preferredHeight

    @SceneStorage(ClaudeDockPanel.sceneStorageKey) private var modeRaw: String =
        ClaudeDockPanel.defaultMode.rawValue

    @AccessibilityFocusState private var contentFocused: Bool

    var mode: TerminalPaneMode {
        TerminalPaneMode(rawValue: modeRaw) ?? Self.defaultMode
    }

    var body: some View {
        VStack(spacing: 0) {
            DockPanelHeader(mode: modeBinding, onClose: close)
            content
        }
        .frame(
            width: Self.preferredWidth,
            height: min(Self.preferredHeight, max(availableHeight - 96, 240))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        .focusable()
        .accessibilityFocused($contentFocused)
        .onAppear { contentFocused = true }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    func close() {
        isOpen = false
    }

    @ViewBuilder
    private var content: some View {
        switch indicatorState {
        case .loading, .ok:
            modeContent
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
            EmbeddedTerminalView(session: terminalSession)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    private var modeBinding: Binding<TerminalPaneMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard mode != newMode else { return }
                modeRaw = newMode.rawValue
            }
        )
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
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
    let terminalSession = TerminalClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true")
    )
    return ClaudeDockPanel(
        session: session,
        terminalSession: terminalSession,
        indicatorState: .loading,
        isOpen: $open
    )
    .padding(40)
}
