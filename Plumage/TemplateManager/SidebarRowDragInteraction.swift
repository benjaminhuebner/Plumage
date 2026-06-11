import SwiftUI

// Pure DragGesture, no LongPress: macOS accessibility three-finger drag has
// no stillness phase, so a sequenced LongPress never activates. 4pt minimum
// distance is the tap-vs-drag discriminator; tap is excluded once drag wins.
struct SidebarRowDragInteraction: ViewModifier {
    var enabled: Bool = true
    let rowID: String
    let payload: SidebarDragPayload
    let drag: SidebarDragController
    let frames: SidebarFrameRegistry
    let onSelect: () -> Void
    let onLiftWillStart: () -> Void
    let onDispatch: (SidebarDragPayload, SidebarDropTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(buildDrag().exclusively(before: buildTap()))
        } else {
            content
        }
    }

    private func buildTap() -> some Gesture {
        TapGesture(count: 1).onEnded { onSelect() }
    }

    private func buildDrag() -> some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(TemplateSidebarLayout.coordinateSpace)
        )
        .onChanged { value in
            if !drag.isActive {
                onLiftWillStart()
                drag.startLift(
                    payload: payload,
                    sourceID: rowID,
                    sourceFrame: frames.rows[rowID] ?? .zero
                )
            }
            drag.updateCursor(location: value.location, translation: value.translation)
        }
        .onEnded { _ in
            guard drag.isActive, let payload = drag.payload else { return }
            if let target = drag.target {
                let sourceFrame = drag.sourceFrame
                let dropTranslation = CGSize(
                    width: target.insertionFrame.minX - sourceFrame.minX,
                    height: target.insertionFrame.minY - sourceFrame.minY
                )
                withAnimation(DragAnimations.drop(reduceMotion: reduceMotion)) {
                    drag.beginDrop(finalTranslation: dropTranslation)
                }
                // Dispatch synchronously so the catalog is at its final
                // layout before the floating overlay clears.
                onDispatch(payload, target)
                drag.scheduleSettle(after: .milliseconds(reduceMotion ? 50 : 180))
            } else {
                withAnimation(DragAnimations.cancel(reduceMotion: reduceMotion)) {
                    drag.beginCancel()
                }
                drag.scheduleSettle(after: .milliseconds(reduceMotion ? 50 : 300))
            }
        }
    }
}
