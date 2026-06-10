import SwiftUI

struct ClaudeDockButton: View {
    static let symbolName = "bubble.left.fill"
    static let glyphGradient = LinearGradient(
        colors: [.orange, .pink, .purple, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    let isWorking: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var accessibilityValueText: String {
        isWorking ? "Working" : "Ready"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: Self.symbolName)
                .foregroundStyle(Self.glyphGradient)
                .font(.system(.title2, design: .default).weight(.semibold))
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .repeat(.continuous),
                    isActive: isWorking && !reduceMotion
                )
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tint(.accentColor)
        .glassEffect(.regular, in: Circle())
        .shadow(color: .accentColor.opacity(0.28), radius: 10, y: 2)
        .overlay(
            Circle().strokeBorder(
                colorSchemeContrast == .increased
                    ? Color.primary.opacity(0.6) : Color.clear,
                lineWidth: 1.5
            )
        )
        .help("Claude (⌥⌘J)")
        .accessibilityLabel("Open Claude")
        .accessibilityValue(accessibilityValueText)
    }
}

#Preview("Idle") {
    ClaudeDockButton(isWorking: false) {}
        .padding(40)
}

#Preview("Working") {
    ClaudeDockButton(isWorking: true) {}
        .padding(40)
}
