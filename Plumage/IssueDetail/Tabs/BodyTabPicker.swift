import SwiftUI

struct BodyTabPicker<Trailing: View>: View {
    @Binding var selectedTab: BodyTab
    var badgeCounts: [BodyTab: Int] = [:]
    @ViewBuilder var trailing: Trailing
    @Namespace private var underlineNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(BodyTab.allCases) { tab in
                    tabButton(for: tab)
                }
                Spacer(minLength: 0)
                trailing
                    .padding(.trailing, 4)
            }
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Body section")
        .accessibilityValue(selectedTab.displayName)
    }

    @ViewBuilder
    private func tabButton(for tab: BodyTab) -> some View {
        let isActive = selectedTab == tab
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: tab.symbolName)
                        .imageScale(.small)
                    Text(tab.displayName)
                        .font(.system(.callout, design: .default).weight(isActive ? .semibold : .regular))
                    if let count = badgeCounts[tab], count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(Color.accentColor)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .accessibilityLabel("\(count) open review comments")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                    if isActive {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

extension BodyTabPicker where Trailing == EmptyView {
    init(selectedTab: Binding<BodyTab>, badgeCounts: [BodyTab: Int] = [:]) {
        self.init(selectedTab: selectedTab, badgeCounts: badgeCounts) { EmptyView() }
    }
}

#Preview {
    StatefulPreviewWrapper(BodyTab.spec) { tab in
        VStack(spacing: 24) {
            BodyTabPicker(selectedTab: tab)
            Text("Selected: \(tab.wrappedValue.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 600)
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
