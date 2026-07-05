import Foundation

// Pure + SwiftUI-free so callers can parse off-main once per load, rather than
// the view re-parsing on every body evaluation.
nonisolated enum MarkdownBlockParser {
    enum Block: Equatable, Sendable {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        case bullet(indent: Int, text: AttributedString)
        case orderedItem(indent: Int, number: Int, text: AttributedString)
        case taskItem(indent: Int, done: Bool, text: AttributedString)
        case table(headers: [AttributedString], rows: [[AttributedString]])
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
            if let table = matchTable(lines, at: &index) {
                blocks.append(table)
                continue
            }
            if line.isEmpty {
                blocks.append(.blank)
            } else if let heading = matchHeading(line) {
                blocks.append(heading)
            } else if let item = matchListItem(line) {
                blocks.append(item)
            } else {
                blocks.append(.paragraph(inlineMarkdown(line)))
            }
            index += 1
        }
        return blocks
    }

    // MARK: - Lists

    private static func matchListItem(_ line: String) -> Block? {
        var spaces = 0
        var start = line.startIndex
        scan: while start < line.endIndex {
            switch line[start] {
            case " ": spaces += 1
            case "\t": spaces += 4
            default: break scan
            }
            start = line.index(after: start)
        }
        let trimmed = String(line[start...])
        let indent = spaces / 2
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let rest = String(trimmed.dropFirst(2))
            if let task = matchTaskMarker(rest) {
                return .taskItem(indent: indent, done: task.done, text: inlineMarkdown(task.text))
            }
            return .bullet(indent: indent, text: inlineMarkdown(rest))
        }
        let digits = trimmed.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 9, let number = Int(digits) {
            let after = trimmed.dropFirst(digits.count)
            if after.hasPrefix(". ") || after.hasPrefix(") ") {
                let text = String(after.dropFirst(2))
                return .orderedItem(indent: indent, number: number, text: inlineMarkdown(text))
            }
        }
        return nil
    }

    private static func matchTaskMarker(_ text: String) -> (done: Bool, text: String)? {
        if text.hasPrefix("[ ] ") || text == "[ ]" {
            return (false, String(text.dropFirst(min(4, text.count))))
        }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") || text == "[x]" || text == "[X]" {
            return (true, String(text.dropFirst(min(4, text.count))))
        }
        return nil
    }

    // MARK: - Tables

    private static func matchTable(_ lines: [String], at index: inout Int) -> Block? {
        guard index + 1 < lines.count else { return nil }
        let headers = tableCells(lines[index])
        guard !headers.isEmpty, isTableDelimiter(lines[index + 1]) else { return nil }
        index += 2
        var rows: [[AttributedString]] = []
        while index < lines.count, !lines[index].isEmpty, lines[index].contains("|") {
            rows.append(tableCells(lines[index]).map(inlineMarkdown))
            index += 1
        }
        return .table(headers: headers.map(inlineMarkdown), rows: rows)
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // Inline formatting (bold/italic/links/inline-code) via AttributedString —
    // NOT LocalizedStringKey, which would reinterpret `%d`, `%@`, `\(…)` in the
    // user content as format specifiers and mangle the output.
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var attributed =
            (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
        sanitizeLinks(&attributed)
        return attributed
    }

    // Only web links stay clickable; file:, javascript:, and relative
    // destinations render as inert text so rendered markdown can never
    // trigger a local open or script through the default-browser handoff.
    private static func sanitizeLinks(_ attributed: inout AttributedString) {
        let disallowed = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let url = run.link else { return nil }
            let scheme = url.scheme?.lowercased()
            return (scheme == "http" || scheme == "https") ? nil : run.range
        }
        for range in disallowed {
            attributed[range].link = nil
        }
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
