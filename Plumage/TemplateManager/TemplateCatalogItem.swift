import Foundation

// What the Template Manager's left column has selected — one of the three tiers.
// Carries ids (not whole values) so it stays a small, stable selection token.
enum TemplateCatalogItem: Hashable, Identifiable {
    case base
    case sharedComponent(String)
    case template(String)

    var id: String {
        switch self {
        case .base: "base"
        case .sharedComponent(let id): "shared:\(id)"
        case .template(let id): "template:\(id)"
        }
    }
}
