import Foundation

// Records a predefined catalog item the user deleted. The bundled default still
// holds the item's definition on disk; the tombstone subtracts it from the
// resolved catalog at merge time, so a "delete predefined" stays reversible
// (restore = drop the tombstone) without copying bundled files. Custom items
// carry no tombstone — deleting them removes their record outright.
nonisolated enum TombstoneKind: String, Codable, Hashable, Sendable {
    case category
    case template
    case sharedComponent
}

nonisolated struct Tombstone: Codable, Hashable, Sendable {
    let kind: TombstoneKind
    let id: String
}
