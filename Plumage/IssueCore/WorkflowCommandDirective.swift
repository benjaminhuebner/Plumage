// Shared by resolver (run-start filtering) and settings editor (badge
// rendering) so both sides agree on what counts as a directive line.
nonisolated enum WorkflowCommandDirective: Equatable, Sendable {
    case open(tokens: [String])
    case elseBranch
    case end

    // A directive occupies its own line; leading/trailing whitespace is
    // tolerated. Tokens after `#if` are type candidates — unknown ones simply
    // match no type, so junk degrades to "matches nothing" instead of failing.
    static func parse(line: String) -> WorkflowCommandDirective? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = tokens.first else { return nil }
        switch first {
        case "#if": return .open(tokens: tokens.dropFirst().map(String.init))
        case "#else": return .elseBranch
        case "#end": return .end
        default: return nil
        }
    }

    func matches(_ type: IssueType) -> Bool {
        switch self {
        case .open(let tokens): return tokens.contains(type.rawValue)
        case .elseBranch, .end: return false
        }
    }
}
