import Foundation

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
