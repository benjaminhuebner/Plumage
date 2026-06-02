import Foundation

// Visual marker for a template/category in the Template Manager. Predefined
// entries use SF Symbols; the case is an enum so #00069 can add custom images
// (asset name, file reference) without touching call sites.
nonisolated enum TemplateImage: Codable, Hashable, Sendable {
    case symbol(String)
}
