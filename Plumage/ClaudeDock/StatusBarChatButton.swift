import SwiftUI

struct StatusBarChatButton: View {
    let isWorking: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: ClaudeDockButton.symbolName)
                .foregroundStyle(ClaudeDockButton.glyphGradient)
                .font(.system(size: 12, weight: .medium))
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .repeat(.continuous),
                    isActive: isWorking && !reduceMotion
                )
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help("Claude (⌥⌘J)")
        .accessibilityLabel("Open Claude")
        .accessibilityValue(isWorking ? "Working" : "Ready")
    }
}

#Preview("Idle") {
    StatusBarChatButton(isWorking: false) {}
        .padding(20)
}

#Preview("Working") {
    StatusBarChatButton(isWorking: true) {}
        .padding(20)
}
