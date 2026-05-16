import SwiftUI

struct TerminalModeToggle: View {
    @Binding var mode: TerminalPaneMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TerminalPaneMode.allCases, id: \.self) { value in
                pill(for: value)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pane mode")
        .accessibilityValue(mode.label)
    }

    @ViewBuilder
    private func pill(for value: TerminalPaneMode) -> some View {
        let isActive = mode == value
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                mode = value
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: value.symbolName)
                    .imageScale(.small)
                Text(value.label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

extension TerminalPaneMode {
    var label: String {
        switch self {
        case .chat: return "Chat"
        case .terminal: return "Terminal"
        }
    }

    var symbolName: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .terminal: return "apple.terminal"
        }
    }
}

#Preview {
    @Previewable @State var mode: TerminalPaneMode = .chat
    return VStack(spacing: 20) {
        TerminalModeToggle(mode: $mode)
        Text("Selected: \(mode.label)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 300)
}
