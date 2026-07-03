// Presentation mapping from catalog values to SF Symbol names. Lives in the UI
// feature folder (not the domain module) because it's a view concern.
extension UserTemplateKind {
    // The icon for this kind's "Add" affordance (toolbar buttons + menu).
    var sfSymbolName: String {
        switch self {
        case .hook: "bolt"
        case .skill: "star"
        case .doc: "doc.text"
        case .agent: "person"
        case .file: "doc.badge.plus"
        case .folder: "folder.badge.plus"
        }
    }
}

extension SharedComponent {
    // Components can mix kinds, so the sidebar uses a single bundle icon.
    var sfSymbolName: String { "shippingbox" }
}

extension SharedComponentKind {
    var displayName: String {
        switch self {
        case .layer: "Layer"
        case .hook: "Hook"
        case .skill: "Skill"
        case .config: "Config"
        }
    }
}
