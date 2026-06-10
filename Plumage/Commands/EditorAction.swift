import Foundation

// Equatable wrapper for closures published via FocusedValues. SwiftUI's
// focusedSceneValue republishes the value whenever the body containing the
// modifier evaluates AND the value differs from the previously published one.
// Plain `() -> Void` has no Equatable conformance, so SwiftUI treats every
// republish as "different" → on cascading state changes within one frame the
// system fires "FocusedValue update tried to update multiple times per frame".
// Wrapping the closure in a UUID-keyed value gives the focus system a stable
// identity to compare across renders.
struct EditorAction: Equatable, Sendable {
    let id: UUID
    // @MainActor-typed instead of @unchecked Sendable on the struct: the
    // actions mutate view state and are only ever invoked from Commands /
    // menu paths, which run on the MainActor anyway.
    let run: @MainActor @Sendable () -> Void

    init(_ run: @escaping @MainActor @Sendable () -> Void) {
        self.id = UUID()
        self.run = run
    }

    static func == (lhs: EditorAction, rhs: EditorAction) -> Bool {
        lhs.id == rhs.id
    }
}
