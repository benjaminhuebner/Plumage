import Foundation

// Turns Finder-dropped file URLs into the text inserted at the session's input
// (terminal or chat). Both destinations are claude *prompts*, not a shell: the
// chat draft is JSON-encoded onto claude's stdin (ClaudeMessageEncoding) and the
// embedded terminal's PTY talks to claude's REPL directly once `exec '<claude>'`
// has replaced /bin/sh. Nothing un-quotes the result, so POSIX shell-escaping
// would only inject literal quote noise into the prompt — and the `'\''` dance
// would actively corrupt any path containing an apostrophe. Instead we insert
// the plain absolute path, wrapped in double quotes only when it contains
// whitespace (issue #00059 "Chat escaping mismatch" edge case). SwiftUI-free so
// both the AppKit terminal view and the SwiftUI chat field can share it.
nonisolated enum DroppedFilePaths {
    // Space-joined, each path quoted only when it contains whitespace, with a
    // trailing space so the user can keep typing after the drop. Empty input
    // yields an empty string (no stray trailing space).
    static func insertionText(for urls: [URL]) -> String {
        guard !urls.isEmpty else { return "" }
        return urls.map { promptQuoted($0.path) }.joined(separator: " ") + " "
    }

    // claude reads the inserted text as a natural-language prompt, so the path
    // stays human-readable: bare when it has no whitespace, double-quoted when it
    // does so a "My File.txt" survives as one token. No shell-style escaping — an
    // embedded apostrophe stays literal (correct here, unlike the shell `'\''`
    // form), and a rare embedded double quote is left as-is rather than mangled
    // with backslashes the prompt would render verbatim.
    static func promptQuoted(_ path: String) -> String {
        guard path.contains(where: \.isWhitespace) else { return path }
        return "\"\(path)\""
    }
}
