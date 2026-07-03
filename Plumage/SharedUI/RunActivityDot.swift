import SwiftUI

struct RunActivityDot: View {
    let color: Color
    let isActive: Bool
    var size: CGFloat = 6

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { isActive && !reduceMotion }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(animates ? (pulsing ? 1.0 : 0.35) : 1.0)
            .animation(
                animates ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : nil,
                value: pulsing
            )
            .onAppear { pulsing = animates }
            .onChange(of: animates) { _, active in pulsing = active }
    }
}

#Preview {
    HStack(spacing: 16) {
        RunActivityDot(color: .green, isActive: true)
        RunActivityDot(color: .orange, isActive: false)
        RunActivityDot(color: .green, isActive: true, size: 8)
    }
    .padding(40)
}
