nonisolated struct DiffLineAnchor: Hashable, Sendable {
    let file: String
    let side: ReviewFinding.Side
    let line: Int

    // Context lines anchor on the new side.
    static func anchors(for hunk: Hunk, file: String) -> [DiffLineAnchor] {
        zip(hunk.lines, DiffLineNumber.numbers(for: hunk)).map { line, number in
            switch line.kind {
            case .added, .context:
                DiffLineAnchor(file: file, side: .new, line: number.new ?? hunk.newStart)
            case .removed:
                DiffLineAnchor(file: file, side: .old, line: number.old ?? hunk.oldStart)
            }
        }
    }
}
