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
        let taskLines = taskTexts.map { "- [ ] " + flattened($0) }
        let lineSeparator = content.contains("\r\n") ? "\r\n" : "\n"
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if let insertionIndex = taskInsertionIndex(in: lines) {
            lines.insert(contentsOf: taskLines, at: insertionIndex)
        } else {
            appendNewSection(taskLines, to: &lines)
        }
        return lines.joined(separator: lineSeparator)
    }

    private static func taskInsertionIndex(in lines: [String]) -> Int? {
        var fenceChar: Character?
        var headerIndex: Int?
        var lastContentIndex: Int?
        for (index, line) in lines.enumerated() {
            if let marker = fenceMarker(line) {
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
                if !line.allSatisfy(\.isWhitespace) { lastContentIndex = index }
            }
        }
        guard let lastContentIndex else { return nil }
        return lastContentIndex + 1
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

    private static func fenceMarker(_ line: String) -> Character? {
        if line.hasPrefix("```") { return "`" }
        if line.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func flattened(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
