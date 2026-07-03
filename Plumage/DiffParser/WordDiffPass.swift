nonisolated public enum WordDiffPass {
    public static func enrich(_ lines: [Line]) -> [Line] {
        let pairs = LinePairing.pairs(in: lines)
        guard !pairs.isEmpty else { return lines }
        var result = lines
        for pair in pairs {
            let removed = lines[pair.removed]
            let added = lines[pair.added]
            guard let changes = TokenDiff.changes(old: removed.content, new: added.content)
            else { continue }
            result[pair.removed] = Line(
                kind: removed.kind,
                content: removed.content,
                tokens: removed.tokens,
                hasNoTrailingNewline: removed.hasNoTrailingNewline,
                changedRanges: changes.removed
            )
            result[pair.added] = Line(
                kind: added.kind,
                content: added.content,
                tokens: added.tokens,
                hasNoTrailingNewline: added.hasNoTrailingNewline,
                changedRanges: changes.inserted
            )
        }
        return result
    }
}
