import SwiftUI

struct ClaudeDockOverlay: View {
    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    var onRecheck: (() -> Void)?
    var showsButton = true
    @Binding var isOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottomPadding: CGFloat = 16
    private static let trailingPadding: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isOpen {
                ClaudeDockPanel(
                    session: session,
                    indicatorState: indicatorState,
                    onRecheck: onRecheck,
                    isOpen: $isOpen
                )
                .background {
                    OutsideClickMonitor(isActive: true, onClickOutside: close)
                        .accessibilityHidden(true)
                }
                .transition(panelTransition)
            } else if showsButton {
                ClaudeDockButton(
                    isWorking: session.awaitingResponse,
                    action: toggle
                )
                .transition(panelTransition)
            }
        }
        .padding(.trailing, Self.trailingPadding)
        .padding(.bottom, Self.bottomPadding)
    }

    func toggle() {
        withAnimation(toggleAnimation) {
            isOpen.toggle()
        }
    }

    func close() {
        withAnimation(toggleAnimation) {
            isOpen = false
        }
    }

    private var panelTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.4, anchor: .bottomTrailing))
    }

    private var toggleAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.1)
            : .spring(response: 0.32, dampingFraction: 0.8)
    }
}

#Preview {
    @Previewable @State var open = false
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        stateDirectory: URL(filePath: "/tmp"),
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
