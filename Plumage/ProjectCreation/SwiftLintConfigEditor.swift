import Foundation

nonisolated enum SwiftLintConfigEditor {
    // Block-style `excluded:` only — the bundled SwiftLint configs never use
    // YAML flow style, so a bare-key + indented-list scan is enough.
    static func addingExclude(_ entry: String, to yaml: String) -> String {
        let trimmedEntry = entry.trimmingCharacters(in: .whitespaces)
        guard !trimmedEntry.isEmpty else { return yaml }

        var lines = yaml.components(separatedBy: "\n")
        guard let keyIndex = lines.firstIndex(where: isExcludedKey) else {
            // A flow-style or commented `excluded:` can't be spliced into safely;
            // leave the file as-is rather than appending a duplicate key.
            if lines.contains(where: hasExcludedKey) { return yaml }
            return appendingExcludedSection(trimmedEntry, to: yaml)
        }

        var lastItemIndex = keyIndex
        var indent = "  "
        var cursor = keyIndex + 1
        while cursor < lines.count, let item = listItem(lines[cursor]) {
            if item.value == trimmedEntry { return yaml }
            indent = item.indent
            lastItemIndex = cursor
            cursor += 1
        }
        lines.insert("\(indent)- \(trimmedEntry)", at: lastItemIndex + 1)
        return lines.joined(separator: "\n")
    }

    private static func isExcludedKey(_ line: String) -> Bool {
        guard let first = line.first, !first.isWhitespace else { return false }
        return line.trimmingCharacters(in: .whitespaces) == "excluded:"
    }

    // Any top-level `excluded:` key, including flow-style (`excluded: [a, b]`) or
    // commented forms that isExcludedKey's bare-key match misses.
    private static func hasExcludedKey(_ line: String) -> Bool {
        guard let first = line.first, !first.isWhitespace else { return false }
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("excluded:")
    }

    private static func listItem(_ line: String) -> (indent: String, value: String)? {
        let indentCount = line.prefix { $0 == " " || $0 == "\t" }.count
        guard indentCount > 0 else { return nil }
        let afterIndent = line.dropFirst(indentCount)
        guard afterIndent.hasPrefix("- ") else { return nil }
        let value = afterIndent.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return (String(line.prefix(indentCount)), value)
    }

    private static func appendingExcludedSection(_ entry: String, to yaml: String) -> String {
        let section = "excluded:\n  - \(entry)\n"
        guard !yaml.isEmpty else { return section }
        let base = yaml.hasSuffix("\n") ? yaml : yaml + "\n"
        return base + "\n" + section
    }
}
