import Foundation

// Pure, disk-free detection of the foundation context files that warn when
// blank: a project's `CLAUDE.md` (root or under `.claude/`) and `PROJECT.md`.
// The relative-path set is explicit so a stray `CLAUDE.md`/`PROJECT.md`
// elsewhere in the tree never false-positives.
nonisolated enum EmptyContextFiles {
    static let targetRelativePaths: Set<String> = [
        ".claude/CLAUDE.md",
        "CLAUDE.md",
        ".claude/docs/PROJECT.md",
    ]

    static func isTarget(relativePath: String) -> Bool {
        targetRelativePaths.contains(relativePath)
    }

    // Empty (0 bytes) or whitespace-only counts as "effectively empty".
    // `allSatisfy` on the empty string is vacuously true, covering 0 bytes.
    static func isEffectivelyEmpty(_ content: String) -> Bool {
        content.allSatisfy(\.isWhitespace)
    }
}
