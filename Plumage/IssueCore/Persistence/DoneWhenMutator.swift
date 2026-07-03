import Foundation

nonisolated enum DoneWhenMutatorError: Error, Equatable, Sendable {
    case criterionNotFound(index: Int)
}

nonisolated enum DoneWhenMutator {
    static func mutate(specURL: URL, criterionIndex: Int, isChecked: Bool) throws {
        let content = try String(contentsOf: specURL, encoding: .utf8)
        let updated = try transform(
            content: content, criterionIndex: criterionIndex, isChecked: isChecked)
        if updated != content {
            try SpecWriter.write(updated, to: specURL)
        }
    }

    static func transform(content: String, criterionIndex: Int, isChecked: Bool) throws -> String {
        let checkboxes = DoneWhenParser.checkboxLines(in: content)
        guard criterionIndex >= 0, criterionIndex < checkboxes.count else {
            throw DoneWhenMutatorError.criterionNotFound(index: criterionIndex)
        }
        let target = checkboxes[criterionIndex]
        if target.isChecked == isChecked { return content }

        let normalized = SpecText.normalizedLines(content: content)
        var lines = normalized.lines
        var characters = Array(lines[target.lineIndex])
        characters[3] = isChecked ? "x" : " "
        lines[target.lineIndex] = String(characters)
        return lines.joined(separator: normalized.separator)
    }
}
