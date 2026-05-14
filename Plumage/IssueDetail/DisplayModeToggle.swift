import SwiftUI

struct DisplayModeToggle: View {
    @Binding var displayMode: IssueDetailView.DisplayMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IssueDetailView.DisplayMode.allCases) { mode in
                pill(for: mode)
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
        .accessibilityLabel("View mode")
        .accessibilityValue(displayMode.rawValue)
    }

    @ViewBuilder
    private func pill(for mode: IssueDetailView.DisplayMode) -> some View {
        let isActive = displayMode == mode
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                displayMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.symbolName)
                    .imageScale(.small)
                Text(mode.rawValue)
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

extension IssueDetailView.DisplayMode {
    var symbolName: String {
        switch self {
        case .detail: "rectangle.grid.1x2"
        case .raw: "chevron.left.forwardslash.chevron.right"
        }
    }
}

#Preview {
    StatefulPreviewWrapper(IssueDetailView.DisplayMode.detail) { mode in
        VStack(spacing: 20) {
            DisplayModeToggle(displayMode: mode)
            Text("Selected: \(mode.wrappedValue.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
