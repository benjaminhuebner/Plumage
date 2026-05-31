import Foundation

// Turns Finder-dropped file URLs into the text inserted at the session's input
// (terminal or chat). Reuses the codebase's POSIX single-quote escaping idiom
// (TerminalClaudeSession.shellQuotedAttachArgs) so a path with spaces, quotes,
// or unicode survives the shell intact. SwiftUI-free so both the AppKit
// terminal view and the SwiftUI chat field can share it.
nonisolated enum DroppedFilePaths {
    // Space-joined, each path single-quote-escaped, with a trailing space so the
    // user can keep typing after the drop. Empty input yields an empty string
    // (no stray trailing space).
    static func insertionText(for urls: [URL]) -> String {
        guard !urls.isEmpty else { return "" }
        return urls.map { shellQuoted($0.path) }.joined(separator: " ") + " "
    }

    // Single-quote wrapping handles every byte literally except an embedded
    // single quote, which is closed, backslash-escaped, and reopened — the
    // standard POSIX `'\''` dance. Robust to newlines (preserved inside quotes),
    // so unlike shellQuotedAttachArgs it needs no isShellSafe precondition.
    static func shellQuoted(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: #"'\''"#)
        return "'\(escaped)'"
    }
}
