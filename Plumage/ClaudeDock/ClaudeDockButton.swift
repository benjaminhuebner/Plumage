import SwiftUI

struct ClaudeDockButton: View {
    static let symbolName = "sparkles"

    let isOpen: Bool
    let isWorking: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var accessibilityLabelText: String {
        isOpen ? "Claude schließen" : "Claude öffnen"
    }

    var accessibilityValueText: String {
        isWorking ? "arbeitet" : "bereit"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: Self.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(.title3, design: .default).weight(.semibold))
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .repeat(.continuous),
                    isActive: isWorking && isOpen && !reduceMotion
                )
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tint(.accentColor)
        .glassEffect(in: Circle())
        .shadow(color: .accentColor.opacity(0.28), radius: 10, y: 2)
        .overlay(
            Circle().strokeBorder(
                colorSchemeContrast == .increased
                    ? Color.primary.opacity(0.6) : Color.clear,
                lineWidth: 1.5
            )
        )
        .help("Claude (⌥⌘T)")
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Idle") {
    ClaudeDockButton(isOpen: false, isWorking: false) {}
        .padding(40)
}

#Preview("Working") {
    ClaudeDockButton(isOpen: true, isWorking: true) {}
        .padding(40)
}
