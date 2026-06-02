import Foundation

// Pure + SwiftUI-free so loadPR can parse off-main once per load, rather than
// the view re-parsing on every body evaluation.
nonisolated enum PRMarkdownParser {
    enum Block: Equatable, Sendable {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        case bullet(AttributedString)
        case codeBlock(String)
        case blank
    }

    static func parse(_ content: String) -> [Block] {
        var blocks: [Block] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                var fenceLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].hasPrefix("```") {
                    fenceLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(fenceLines.joined(separator: "\n")))
                if index < lines.count { index += 1 }
                continue
            }
            if line.isEmpty {
                blocks.append(.blank)
            } else if let heading = matchHeading(line) {
                blocks.append(heading)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(inlineMarkdown(String(line.dropFirst(2)))))
            } else {
                blocks.append(.paragraph(inlineMarkdown(line)))
            }
            index += 1
        }
        return blocks
    }

    // Inline formatting (bold/italic/links/inline-code) via AttributedString —
    // NOT LocalizedStringKey, which would reinterpret `%d`, `%@`, `\(…)` in the
    // user content as format specifiers and mangle the output.
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }

    private static func matchHeading(_ line: String) -> Block? {
        var level = 0
        for char in line {
            guard char == "#" else { break }
            level += 1
        }
        guard level >= 1, level <= 6, line.count > level,
            line[line.index(line.startIndex, offsetBy: level)] == " "
        else {
            return nil
        }
        let text = line.dropFirst(level + 1).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: inlineMarkdown(text))
    }
}
