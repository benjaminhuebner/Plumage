import SwiftUI

struct ClaudeDockPanel: View {
    static let preferredWidth: CGFloat = 420
    static let preferredHeight: CGFloat = 560

    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    @Binding var isOpen: Bool

    @AccessibilityFocusState private var contentFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            DockPanelHeader(onClose: close)
            content
        }
        .frame(width: Self.preferredWidth, height: Self.preferredHeight)
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
            chatContent
        case .missing, .unsupported, .failed:
            MissingClaudeView(state: indicatorState)
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        ChatView(session: session)
            .overlay(alignment: .top) {
                if case .exited(let code, let reason) = session.state {
                    ExitBanner(code: code, reason: reason) {
                        session.restart()
                    }
                }
            }
    }
}

private struct DockPanelHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
