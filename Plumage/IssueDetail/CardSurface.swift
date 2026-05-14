import SwiftUI

struct CardSurfaceModifier: ViewModifier {
    let tintColor: Color

    // Guard against unbalanced push/pop: if hovering=true fires twice
    // without an intervening hovering=false (view re-created mid-hover,
    // overlay covers the card, sheet pops, etc.) the cursor stack would
    // grow until the next manual reset. We only push/pop on transitions.
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
            // Static shadow — no hover-dependent change. The previous
            // hover animation (shadow y 2→3, radius 4→8, scale 1.0→1.01
            // with .smooth(0.18)) fired the moment a card materialised
            // under the cursor right after drop, which read as a
            // "fall-down / settling" effect on the just-placed card.
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                // Card removed while still hovered (drop animation, scroll
                // out of view, window close) — pop our own push to keep
                // the cursor stack balanced.
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

extension View {
    func cardSurface(tint: Color) -> some View {
        modifier(CardSurfaceModifier(tintColor: tint))
    }
}

#Preview {
    VStack(spacing: 12) {
        Text("Green tint")
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(tint: .green)
        Text("Yellow tint")
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(tint: .yellow)
        Text("Red tint")
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(tint: .red)
    }
    .padding()
    .frame(width: 280)
}
