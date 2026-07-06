nonisolated enum ChatButtonPlacement: String, CaseIterable, Identifiable {
    case floating
    case statusBar

    static let storageKey = "chatButtonPlacement"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floating: "Floating"
        case .statusBar: "Status Bar"
        }
    }

    var systemImage: String {
        switch self {
        case .floating: "rectangle.inset.bottomright.filled"
        case .statusBar: "rectangle.bottomthird.inset.filled"
        }
    }
}
