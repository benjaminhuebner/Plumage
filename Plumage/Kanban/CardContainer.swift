import SwiftUI

struct CardContainerModifier: ViewModifier {
    let tintColor: Color
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                LinearGradient(
                    colors: [
                        tintColor.opacity(0.10),
                        Color(NSColor.controlBackgroundColor),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
            .shadow(
                color: .black.opacity(isHovering ? 0.10 : 0.06),
                radius: isHovering ? 8 : 4,
                x: 0,
                y: isHovering ? 3 : 2
            )
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.smooth(duration: 0.18), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    func cardContainer(tint: Color) -> some View {
        modifier(CardContainerModifier(tintColor: tint))
    }
}

#Preview {
    VStack(spacing: 12) {
        Text("Green tint")
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardContainer(tint: .green)
        Text("Yellow tint")
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardContainer(tint: .yellow)
        Text("Red tint")
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardContainer(tint: .red)
    }
    .padding()
    .frame(width: 280)
}
