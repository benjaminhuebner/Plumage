import SwiftUI

// Reminders/Calendar-style color control: a round swatch that pops a palette
// of system colors, with the native panel behind "Custom" for everything else.
struct IssueTypeColorSwatch: View {
    @Binding var color: Color
    let accessibilityLabel: String

    @State private var popoverShown = false
    @State private var hovering = false

    private static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .brown,
    ]

    var body: some View {
        Button {
            popoverShown = true
        } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                .overlay {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(hovering ? 0.9 : 0))
                        .accessibilityHidden(true)
                }
                .shadow(color: .black.opacity(hovering ? 0.25 : 0), radius: 2, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Choose a color")
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $popoverShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 6),
                    spacing: 8
                ) {
                    ForEach(Self.palette, id: \.self) { swatch in
                        swatchButton(swatch)
                    }
                }
                Divider()
                ColorPicker("Custom", selection: $color, supportsOpacity: false)
                    .font(.callout)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func swatchButton(_ swatch: Color) -> some View {
        let isSelected = swatch.issueTypeHexString == color.issueTypeHexString
        Button {
            color = swatch
            popoverShown = false
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                }
                Circle()
                    .fill(swatch)
                    .frame(width: 17, height: 17)
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatchName(swatch))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func swatchName(_ swatch: Color) -> String {
        swatch.description.capitalized
    }
}

#Preview {
    StatefulPreviewWrapper(Color.green) { color in
        IssueTypeColorSwatch(color: color, accessibilityLabel: "Color")
            .padding(40)
    }
}
