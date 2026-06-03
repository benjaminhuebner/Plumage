import Foundation

// What kind of asset a shared component contributes to a template's effective
// scaffold. `layer` => a `CLAUDE.md` layer file; `hook` => one or more hook
// scripts; `skill`/`config` are reserved for later authoring (#00069).
nonisolated enum SharedComponentKind: String, Codable, Hashable, Sendable, CaseIterable {
    case layer
    case hook
    case skill
    case config
}

// The middle tier: a reusable building block included in a selectable subset of
// templates. `memberTemplateIDs` is the explicit per-template membership; `order`
// fixes the concatenation position so composed layers stay byte-stable.
nonisolated struct SharedComponent: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var name: String
    let kind: SharedComponentKind
    // For `.layer`: layer base names (e.g. "swift-shared"). For `.hook`: hook base names.
    var files: [String]
    var order: Int
    var memberTemplateIDs: Set<String>

    func isMember(_ templateID: String) -> Bool { memberTemplateIDs.contains(templateID) }
}
