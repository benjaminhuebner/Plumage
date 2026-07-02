import Foundation

nonisolated struct DoneWhenCriterion: Sendable, Equatable {
    let text: String
    let isChecked: Bool
}

nonisolated enum DoneWhenParser {
    nonisolated struct CheckboxLine: Sendable, Equatable {
        let lineIndex: Int
        let text: String
        let isChecked: Bool
    }

    static func criteria(in content: String) -> [DoneWhenCriterion] {
        checkboxLines(in: content).map { DoneWhenCriterion(text: $0.text, isChecked: $0.isChecked) }
    }

    // Indices count CRLF-normalized lines; mutating callers must normalize
    // the same way or the index addresses the wrong line.
    static func checkboxLines(in content: String) -> [CheckboxLine] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [CheckboxLine] = []
        var inSection = false
        var fenceChar: Character?
        for (index, line) in lines.enumerated() {
            if !inSection {
                if isDoneWhenHeader(line) { inSection = true }
                continue
            }
            if let marker = fenceMarker(line) {
                if fenceChar == nil {
                    fenceChar = marker
                } else if fenceChar == marker {
                    fenceChar = nil
                }
                continue
            }
            if fenceChar != nil { continue }
            if line.hasPrefix("## ") { break }
            if let checkbox = parseCheckbox(line, at: index) {
                result.append(checkbox)
            }
        }
        return result
    }

    private static func isDoneWhenHeader(_ line: String) -> Bool {
        guard line.hasPrefix("## Done when") else { return false }
        return line.dropFirst("## Done when".count).allSatisfy(\.isWhitespace)
    }

    private static func fenceMarker(_ line: String) -> Character? {
        if line.hasPrefix("```") { return "`" }
        if line.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func parseCheckbox(_ line: String, at index: Int) -> CheckboxLine? {
        let isChecked: Bool
        if line.hasPrefix("- [ ]") {
            isChecked = false
        } else if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") {
            isChecked = true
        } else {
            return nil
        }
        let text = line.dropFirst("- [ ]".count).trimmingCharacters(in: .whitespaces)
        return CheckboxLine(lineIndex: index, text: text, isChecked: isChecked)
    }
}
