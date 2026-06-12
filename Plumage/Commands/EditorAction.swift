import Foundation

// Equatable wrapper for FocusedValues closures: plain `() -> Void` isn't Equatable,
// so every republish counts as "different" and cascading state changes fire
// "FocusedValue update tried to update multiple times per frame" — a UUID key gives stable identity.
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
