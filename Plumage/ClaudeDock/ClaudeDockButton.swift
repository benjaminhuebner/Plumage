import SwiftUI

struct ClaudeDockButton: View {
    static let symbolName = "apple.intelligence"

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
                .symbolRenderingMode(.multicolor)
                .font(.system(.title2, design: .default).weight(.semibold))
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .repeat(.continuous),
                    isActive: isWorking && !isOpen && !reduceMotion
                )
                .opacity(isOpen ? 0 : 1)
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
        .help("Claude (⌥⌘J)")
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
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
