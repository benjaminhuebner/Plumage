import SwiftUI

struct ClaudeDockButton: View {
    static let symbolName = "sparkles"

    let isOpen: Bool
    let isWorking: Bool
    let action: () -> Void

    var accessibilityLabelForTesting: String {
        isOpen ? "Claude schließen" : "Claude öffnen"
    }

    var accessibilityValueForTesting: String {
        isWorking ? "arbeitet" : "bereit"
    }

    func invokeForTesting() { action() }

    var body: some View {
        Button(action: action) {
            Image(systemName: Self.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 20, weight: .semibold))
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .repeat(.continuous),
                    isActive: isWorking
                )
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tint(.accentColor)
        .glassEffect(in: Circle())
        .shadow(color: .accentColor.opacity(0.28), radius: 10, y: 2)
        .help("Claude (⌥⌘T)")
        .accessibilityLabel(accessibilityLabelForTesting)
        .accessibilityValue(accessibilityValueForTesting)
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
