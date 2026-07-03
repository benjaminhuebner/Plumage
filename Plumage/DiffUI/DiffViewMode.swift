nonisolated enum DiffViewMode: String, CaseIterable, Identifiable {
    case unified
    case sideBySide

    static let storageKey = "diff.viewMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unified: return "Unified"
        case .sideBySide: return "Side by Side"
        }
    }

    var symbolName: String {
        switch self {
        case .unified: return "text.justify"
        case .sideBySide: return "rectangle.split.2x1"
        }
    }

    var helpText: String {
        switch self {
        case .unified: return "Unified diff"
        case .sideBySide: return "Side-by-side diff"
        }
    }
}
