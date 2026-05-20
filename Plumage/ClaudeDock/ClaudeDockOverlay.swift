import SwiftUI

struct ClaudeDockOverlay: View {
    let session: ClaudeSession
    let terminalSession: TerminalClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    @Binding var isOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var availableHeight: CGFloat = ClaudeDockPanel.preferredHeight

    private static let buttonBottomPadding: CGFloat = 16
    private static let buttonTrailingPadding: CGFloat = 16
    // 16pt safe-area + 48pt button + 12pt gap = 76pt.
    private static let panelBottomPadding: CGFloat = 76
    private static let panelTrailingPadding: CGFloat = 16

    var body: some View {
        GlassEffectContainer {
            ZStack(alignment: .bottomTrailing) {
                // Full-frame anchor so .bottomTrailing has something to pin to.
                // onGeometryChange feeds the panel the live window height so
                // it can shrink at minHeight=560 instead of overflowing the
                // window's top edge.
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        availableHeight = height
                    }
                // Always mounted — visibility is purely an opacity flip so
                // both ClaudeSession (chat) and TerminalClaudeSession
                // (terminal) stay attached to a live SwiftUI view tree across
                // dock open/close cycles.
                ClaudeDockPanel(
                    session: session,
                    terminalSession: terminalSession,
                    indicatorState: indicatorState,
                    isOpen: $isOpen,
                    availableHeight: availableHeight
                )
                .padding(.trailing, Self.panelTrailingPadding)
                .padding(.bottom, Self.panelBottomPadding)
                .opacity(isOpen ? 1 : 0)
                .scaleEffect(panelScale, anchor: .bottomTrailing)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
                ClaudeDockButton(
                    isOpen: isOpen,
                    isWorking: session.awaitingResponse,
                    action: toggle
                )
                .padding(.trailing, Self.buttonTrailingPadding)
                .padding(.bottom, Self.buttonBottomPadding)
            }
        }
    }

    func toggle() {
        withAnimation(toggleAnimation) {
            isOpen.toggle()
        }
    }

    private var toggleAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.1)
            : .spring(response: 0.35, dampingFraction: 0.78)
    }

    private var panelScale: CGFloat {
        if reduceMotion { return 1 }
        return isOpen ? 1 : 0.05
    }
}

#Preview {
    @Previewable @State var open = false
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        autoSpawn: false
    )
    let terminalSession = TerminalClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true")
    )
    return Color.gray.opacity(0.1)
        .overlay(alignment: .bottomTrailing) {
            ClaudeDockOverlay(
                session: session,
                terminalSession: terminalSession,
                indicatorState: .loading,
                isOpen: $open
            )
        }
        .frame(width: 900, height: 700)
}
