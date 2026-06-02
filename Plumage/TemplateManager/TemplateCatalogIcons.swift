import Foundation

// Presentation mapping from catalog values to SF Symbol names. Lives in the UI
// feature folder (not the domain module) because it's a view concern.
extension TemplateImage {
    var sfSymbolName: String {
        switch self {
        case .symbol(let name): name
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
}
