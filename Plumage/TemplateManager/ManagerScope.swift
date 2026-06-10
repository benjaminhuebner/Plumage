import Foundation

// Which template-manager tier owns a loose (untyped) file. Each tier roots its loose
// files under a distinct store prefix, so a file authored in one tier no longer leaks
// into every template. Base keeps the historical flat root (`""`); a Template
// and a Shared Component each own a private subtree. The composition assets (layers,
// hooks, configs) are *not* scoped through here — they stay membership-correct as-is.
nonisolated enum ManagerScope: Hashable, Sendable {
    case base
    case template(String)
    case component(String)

    // The override-store prefix loose files of this scope live under. Empty for Base
    // (its loose dirs sit at the store root, no migration); a per-id subtree otherwise.
    var storageRoot: String {
        switch self {
        case .base: return ""
        case .template(let id): return "templates/\(id)"
        case .component(let id): return "components/\(id)"
        }
    }

    // The scope a left-column selection owns its loose files in.
    static func scope(for item: TemplateCatalogItem) -> ManagerScope {
        switch item {
        case .base: return .base
        case .template(let id): return .template(id)
        case .sharedComponent(let id): return .component(id)
        }
    }
}
