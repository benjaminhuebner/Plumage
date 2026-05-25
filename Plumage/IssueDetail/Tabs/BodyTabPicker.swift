import SwiftUI

struct BodyTabPicker: View {
    @Binding var selectedTab: BodyTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BodyTab.allCases) { tab in
                pill(for: tab)
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
        .accessibilityLabel("Body section")
        .accessibilityValue(selectedTab.displayName)
    }

    @ViewBuilder
    private func pill(for tab: BodyTab) -> some View {
        let isActive = selectedTab == tab
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbolName)
                    .imageScale(.small)
                Text(tab.displayName)
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

#Preview {
    StatefulPreviewWrapper(BodyTab.spec) { tab in
        VStack(spacing: 20) {
            BodyTabPicker(selectedTab: tab)
            Text("Selected: \(tab.wrappedValue.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 400)
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
