import Foundation

// Read-only membership facts for the middle column: for a template, the shared
// components it includes; for a shared component, the templates that include it.
struct CatalogMembership: Equatable {
    let title: String
    let names: [String]
}
