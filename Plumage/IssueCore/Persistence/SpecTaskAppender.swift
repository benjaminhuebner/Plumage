import Foundation

nonisolated enum SpecTaskAppenderError: Error, Equatable, Sendable {
    case noTasksToAppend
}

nonisolated enum SpecTaskAppender {
    static func appendReviewFixTasks(specURL: URL, taskTexts: [String]) throws {
        let content = try String(contentsOf: specURL, encoding: .utf8)
        let updated = try transform(content: content, taskTexts: taskTexts)
        if updated != content {
            try SpecWriter.write(updated, to: specURL)
        }
    }

    static func transform(content: String, taskTexts: [String]) throws -> String {
        guard !taskTexts.isEmpty else { throw SpecTaskAppenderError.noTasksToAppend }
        let normalized = SpecText.normalizedLines(content: content)
        var lines = normalized.lines
        let section = scanTasksSection(in: lines)
        // Retry-safe: when the append landed but the follow-up status commit
        // failed, the caller retries the whole request — task lines already in
        // the section must not duplicate.
        let existing = section?.existingLines ?? []
        let taskLines = taskTexts.map { "- [ ] " + flattened($0) }
            .filter { !existing.contains($0) }
        guard !taskLines.isEmpty else { return content }
        if let section {
            lines.insert(contentsOf: taskLines, at: section.insertionIndex)
        } else {
            appendNewSection(taskLines, to: &lines)
        }
        return lines.joined(separator: normalized.separator)
    }

    private static func scanTasksSection(
        in lines: [String]
    ) -> (insertionIndex: Int, existingLines: Set<String>)? {
        var fenceChar: Character?
        var headerIndex: Int?
        var lastContentIndex: Int?
        // Fenced lines advance the insertion point but never count as
        // existing tasks — a checkbox inside a code block is an example.
        var existingLines: Set<String> = []
        for (index, line) in lines.enumerated() {
            if let marker = SpecText.fenceMarker(line) {
                if fenceChar == nil {
                    fenceChar = marker
                } else if fenceChar == marker {
                    fenceChar = nil
                }
                if headerIndex != nil { lastContentIndex = index }
                continue
            }
            if fenceChar != nil {
                if headerIndex != nil { lastContentIndex = index }
                continue
            }
            if headerIndex == nil {
                if isTasksHeader(line) {
                    headerIndex = index
                    lastContentIndex = index
                }
            } else {
                if line.hasPrefix("## ") { break }
                if !line.allSatisfy(\.isWhitespace) {
                    lastContentIndex = index
                    existingLines.insert(line)
                }
            }
        }
        guard let lastContentIndex else { return nil }
        return (lastContentIndex + 1, existingLines)
    }

    private static func appendNewSection(_ taskLines: [String], to lines: inout [String]) {
        let hadTrailingNewline = lines.count > 1 && lines.last?.isEmpty == true
        if hadTrailingNewline { lines.removeLast() }
        if let last = lines.last, !last.allSatisfy(\.isWhitespace) {
            lines.append("")
        }
        lines.append("## Tasks")
        lines.append("")
        lines.append(contentsOf: taskLines)
        if hadTrailingNewline { lines.append("") }
    }

    private static func isTasksHeader(_ line: String) -> Bool {
        guard line.hasPrefix("## Tasks") else { return false }
        return line.dropFirst("## Tasks".count).allSatisfy(\.isWhitespace)
    }

    private static func flattened(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
