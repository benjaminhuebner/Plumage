import SwiftUI

struct ClaudeDockOverlay: View {
    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    @Binding var isOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var dockNamespace

    private static let buttonBottomPadding: CGFloat = 16
    private static let buttonTrailingPadding: CGFloat = 16
    private static let panelBottomPadding: CGFloat = 16
    private static let panelTrailingPadding: CGFloat = 16
    private static let glassMorphID = "claude-dock"

    var body: some View {
        GlassEffectContainer {
            ZStack(alignment: .bottomTrailing) {
                OutsideClickMonitor(isActive: isOpen, onClickOutside: close)
                    .frame(
                        width: ClaudeDockPanel.preferredWidth,
                        height: ClaudeDockPanel.preferredHeight
                    )
                    .padding(.trailing, Self.panelTrailingPadding)
                    .padding(.bottom, Self.panelBottomPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ClaudeDockPanel(
                    session: session,
                    indicatorState: indicatorState,
                    isOpen: $isOpen
                )
                .glassEffectID(Self.glassMorphID, in: dockNamespace)
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
                .glassEffectID(Self.glassMorphID, in: dockNamespace)
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

    func close() {
        withAnimation(toggleAnimation) {
            isOpen = false
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
