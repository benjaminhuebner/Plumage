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
                if isOpen {
                    ClaudeDockPanel(
                        session: session,
                        indicatorState: indicatorState,
                        isOpen: $isOpen
                    )
                    .glassEffectID(Self.glassMorphID, in: dockNamespace)
                    .padding(.trailing, Self.panelTrailingPadding)
                    .padding(.bottom, Self.panelBottomPadding)
                    .background {
                        OutsideClickMonitor(isActive: true, onClickOutside: close)
                            .accessibilityHidden(true)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottomTrailing)))
                } else {
                    ClaudeDockButton(
                        isOpen: false,
                        isWorking: session.awaitingResponse,
                        action: toggle
                    )
                    .glassEffectID(Self.glassMorphID, in: dockNamespace)
                    .padding(.trailing, Self.buttonTrailingPadding)
                    .padding(.bottom, Self.buttonBottomPadding)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottomTrailing)))
                }
            }
        }
        .animation(toggleAnimation, value: isOpen)
    }

    func toggle() {
        isOpen.toggle()
    }

    func close() {
        isOpen = false
    }

    private var toggleAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.1)
            : .spring(response: 0.55, dampingFraction: 0.78)
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
