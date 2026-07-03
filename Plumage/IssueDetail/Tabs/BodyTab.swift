enum BodyTab: String, CaseIterable, Identifiable, Sendable {
    case prompt
    case spec
    case pullRequest
    case diff

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prompt: return "Prompt"
        case .spec: return "Spec"
        case .pullRequest: return "Pull Request"
        case .diff: return "Diff"
        }
    }

    var symbolName: String {
        switch self {
        case .prompt: return "lightbulb"
        case .spec: return "doc.text"
        case .pullRequest: return "arrow.triangle.pull"
        case .diff: return "plus.forwardslash.minus"
        }
    }
}
