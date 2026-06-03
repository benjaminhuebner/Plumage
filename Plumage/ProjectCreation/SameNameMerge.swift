import Foundation

// Combines the same-named, non-`CLAUDE.md` text files that several active layers
// each contribute into one document. `CLAUDE.md` itself uses the richer section
// merge (`ClaudeMdComposer`); every other Markdown/text file a layer carries is
// merged here by trimming each fragment and joining them in layer order with a
// Markdown `---` thematic break. Pure and SwiftUI-free so it stays testable.
nonisolated enum SameNameMerge {
    static let separator = "\n\n---\n\n"

    // Merge `fragments` (one per contributing layer, already in layer order) into a
    // single text file body. Blank fragments are dropped so an empty layer adds no
    // stray separator. The result carries a trailing newline unless every fragment
    // was blank, in which case it is empty.
    static func mergeText(_ fragments: [String]) -> String {
        let trimmed =
            fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "" }
        return trimmed.joined(separator: separator) + "\n"
    }
}
