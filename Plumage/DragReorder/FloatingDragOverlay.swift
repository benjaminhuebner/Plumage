import SwiftUI

// Renders the lifted row 1:1 under the cursor instead of a system drag
// preview ghost. Reads the controller only in its own body, so the host
// view's body does not re-evaluate on every cursor frame.
struct FloatingDragOverlay<Payload, Target: Equatable, Content: View>: View {
    let controller: DragReorderController<Payload, Target>
    @ViewBuilder var content: (Payload) -> Content

    var body: some View {
        if controller.isActive, let payload = controller.payload {
            content(payload)
                .frame(width: controller.sourceFrame.width, height: controller.sourceFrame.height)
                .scaleEffect(controller.status == .cancelling ? 1.0 : 1.04)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                .offset(
                    x: controller.sourceFrame.minX + controller.translation.width,
                    y: controller.sourceFrame.minY + controller.translation.height
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
