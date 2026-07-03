import Foundation

nonisolated enum ReviewFindingStaleness {
    static func isStale(_ finding: ReviewFinding, in files: [FileDiff]) -> Bool {
        guard let file = files.first(where: { $0.path == finding.file }) else { return true }
        for hunk in file.hunks {
            for line in hunk.lines
            where line.content == finding.lineText && sideMatches(line.kind, finding.side) {
                return false
            }
        }
        return true
    }

    private static func sideMatches(_ kind: LineKind, _ side: ReviewFinding.Side) -> Bool {
        switch kind {
        case .added: side == .new
        case .removed: side == .old
        case .context: true
        }
    }
}
