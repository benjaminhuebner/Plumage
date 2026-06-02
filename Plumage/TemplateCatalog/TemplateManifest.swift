import Foundation

// The persisted catalog structure. Absent on a fresh install (the store then
// uses the bundled default). Lives under Application Support, never the Claude
// config directory (CCI boundary stays intact).
//
// Forward-compat: #00069 will add tombstones (removed-predefined IDs) and custom
// authoring. Unknown keys written by a newer Plumage are ignored on decode here;
// a manifest that fails to decode is handled by the store (falls back to bundled).
nonisolated struct TemplateManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let base: BaseTemplate
    let categories: [TemplateCategory]
    let sharedComponents: [SharedComponent]
    let templates: [TemplateDescriptor]
}
