import SwiftUI

struct ClaudeDockOverlay: View {
    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    @Binding var isOpen: Bool

    private static let buttonBottomPadding: CGFloat = 16
    private static let buttonTrailingPadding: CGFloat = 16
    // 16pt safe-area + 48pt button + 12pt gap = 76pt.
    private static let panelBottomPadding: CGFloat = 76
    private static let panelTrailingPadding: CGFloat = 16

    var body: some View {
        // Two siblings instead of nested overlays so each gets its own
        // hit area; the panel does not capture taps outside its frame.
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if isOpen {
                ClaudeDockPanel(
                    session: session,
                    indicatorState: indicatorState,
                    isOpen: $isOpen
                )
                .padding(.trailing, Self.panelTrailingPadding)
                .padding(.bottom, Self.panelBottomPadding)
                .transition(
                    .scale(scale: 0.05, anchor: .bottomTrailing)
                        .combined(with: .opacity)
                )
            }
            ClaudeDockButton(
                isOpen: isOpen,
                isWorking: session.awaitingResponse,
                action: toggle
            )
            .padding(.trailing, Self.buttonTrailingPadding)
            .padding(.bottom, Self.buttonBottomPadding)
        }
        .allowsHitTesting(true)
    }

    private func toggle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            isOpen.toggle()
        }
    }

    func toggleForTesting() { toggle() }
}

#Preview {
    @Previewable @State var open = false
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        autoSpawn: false
    )
    return Color.gray.opacity(0.1)
        .overlay(alignment: .bottomTrailing) {
            ClaudeDockOverlay(
                session: session,
                indicatorState: .loading,
                isOpen: $open
            )
        }
        .frame(width: 900, height: 700)
}
