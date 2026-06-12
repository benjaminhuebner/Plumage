import SwiftUI

// Selection + hover parity with the List rows this surface replaced: accent
// selection capsule with white content, quiet hover wash, 18pt icon slot.
struct SidebarItemRow<Icon: View>: View {
    let title: String
    let isSelected: Bool
    var hoverEnabled: Bool = true
    @ViewBuilder var icon: () -> Icon

    @State private var isHovering = false
    @Environment(\.controlActiveState) private var controlActiveState

    // Semantic, not .white: the system colors adapt to accent/contrast
    // settings and to the window losing key state.
    private var selectedContentStyle: AnyShapeStyle {
        controlActiveState == .key
            ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
            : AnyShapeStyle(.primary)
    }

    private var selectionFill: Color {
        controlActiveState == .key
            ? Color(nsColor: .selectedContentBackgroundColor)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    var body: some View {
        HStack(spacing: 7) {
            icon()
                .foregroundStyle(
                    isSelected ? selectedContentStyle : AnyShapeStyle(Color.accentColor)
                )
                .frame(width: 18, height: 18)
            Text(title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? selectedContentStyle : AnyShapeStyle(.primary))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectionFill)
            } else if hoverEnabled && isHovering {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
