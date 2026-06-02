import Foundation

// A grouping of templates in the catalog's third tier (e.g. "Apple Apps").
// `order` drives deterministic left-column ordering.
nonisolated struct TemplateCategory: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let order: Int
}
