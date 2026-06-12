import Foundation

// Records a predefined catalog item the user deleted. The bundled default still
// holds the item's definition on disk; the tombstone subtracts it from the
// resolved catalog at merge time, so a "delete predefined" stays reversible
// (restore = drop the tombstone) without copying bundled files. Custom items
// carry no tombstone — deleting them removes their record outright.
// A kind string this build doesn't know is almost always an archive exported
// by a newer Plumage — the importer must say that, not "invalid manifest".
nonisolated struct UnknownKindError: Error, Equatable {
    let field: String
    let value: String
}

nonisolated enum TombstoneKind: String, Codable, Hashable, Sendable {
    case category
    case template
    case sharedComponent

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let kind = Self(rawValue: raw) else {
            throw UnknownKindError(field: "deleted-item kind", value: raw)
        }
        self = kind
    }
}

nonisolated struct Tombstone: Codable, Hashable, Sendable {
    let kind: TombstoneKind
    let id: String
}
