import Foundation

// Presentation mapping from catalog values to SF Symbol names. Lives in the UI
// feature folder (not the domain module) because it's a view concern.
extension TemplateImage {
    // The SF Symbol to show. A `.file` image has no symbol — callers that can render
    // the imported image use `TemplateImageView`; this is the list/menu fallback.
    var sfSymbolName: String {
        switch self {
        case .symbol(let name): name
        case .file: "photo"
        }
    }
}

extension UserTemplateKind {
    // The icon for this kind's "Add" affordance (toolbar buttons + menu).
    var sfSymbolName: String {
        switch self {
        case .hook: "bolt"
        case .skill: "star"
        case .doc: "doc.text"
        case .script: "terminal"
        case .agent: "person"
        case .file: "doc.badge.plus"
        case .folder: "folder.badge.plus"
        }
    }
}

extension SharedComponentKind {
    var sfSymbolName: String {
        switch self {
        case .layer: "doc.text"
        case .hook: "bolt"
        case .skill: "star"
        case .config: "gearshape"
        }
    }

    var displayName: String {
        switch self {
        case .layer: "Layer"
        case .hook: "Hook"
        case .skill: "Skill"
        case .config: "Config"
        }
    }
}
