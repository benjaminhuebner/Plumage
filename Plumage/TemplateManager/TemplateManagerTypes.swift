import Foundation

// Value types shared between TemplateManagerModel and the manager's views.

// Read-only membership facts for the middle column: for a template, the shared
// components it includes; for a shared component, the templates that include it.
struct CatalogMembership: Equatable {
    let title: String
    let names: [String]
}

// Inline-rename session for a sidebar category header. `id` is the category id;
// `name` is bound by the header's `TextField`.
struct CategoryRename: Identifiable, Equatable {
    let id: String
    var name: String
}

// Inline-rename session for a content-tree row. `id` is the node id; `storePath` is the
// override-store path of the file/folder being renamed; `name` is bound by the row's
// `TextField`.
struct ContentRename: Identifiable, Equatable {
    let id: String
    let storePath: String
    let isDirectory: Bool
    var name: String
}

// A deleted predefined item offered in the Restore menu.
struct RestorableItem: Identifiable, Hashable {
    let kind: TombstoneKind
    let itemID: String
    let name: String

    var id: String { "\(kind):\(itemID)" }

    var menuLabel: String {
        let noun =
            switch kind {
            case .category: "Category"
            case .template: "Template"
            case .sharedComponent: "Shared Component"
            }
        return "\(name) (\(noun))"
    }
}
