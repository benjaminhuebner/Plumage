import Foundation

nonisolated enum SpecText {
    static func fenceMarker(_ line: String) -> Character? {
        if line.hasPrefix("```") { return "`" }
        if line.hasPrefix("~~~") { return "~" }
        return nil
    }

    // Preserve the original line-ending convention: callers re-join with the
    // returned separator, so a rewrite of a CRLF file doesn't silently flip
    // its line endings.
    static func normalizedLines(content: String) -> (lines: [String], separator: String) {
        let separator = content.contains("\r\n") ? "\r\n" : "\n"
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        return (lines, separator)
    }
}
