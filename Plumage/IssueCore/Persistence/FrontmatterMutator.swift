import Foundation

nonisolated enum SetValue<T: Sendable>: Sendable {
    case keep
    case set(T)
}

extension SetValue: Equatable where T: Equatable {}
extension SetValue: Hashable where T: Hashable {}

nonisolated enum MutatorError: Error, Equatable, Sendable {
    case noFrontmatter
}

nonisolated enum FrontmatterMutator {
    static func mutate(
        specURL: URL,
        newStatus: IssueStatus?,
        newOrder: SetValue<Double?>,
        now: Date
    ) throws {
        let content = try String(contentsOf: specURL, encoding: .utf8)
        let updated = try transform(
            content: content,
            newStatus: newStatus,
            newOrder: newOrder,
            now: now
        )
        try SpecWriter.write(updated, to: specURL)
    }

    static func transform(
        content: String,
        newStatus: IssueStatus?,
        newOrder: SetValue<Double?>,
        now: Date
    ) throws -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        // Preserve the original line-ending convention: if any \r\n existed,
        // emit \r\n on output so we don't silently flip line endings.
        let lineSeparator = content.contains("\r\n") ? "\r\n" : "\n"

        let lines = normalized.components(separatedBy: "\n")
        guard let frontStart = firstDelimiterIndex(in: lines),
            let frontEnd = secondDelimiterIndex(in: lines, after: frontStart)
        else {
            throw MutatorError.noFrontmatter
        }

        var frontmatter = Array(lines[(frontStart + 1)..<frontEnd])
        var sawStatus = false
        var sawOrder = false
        var sawUpdated = false
        var statusIndex: Int?

        let nowString = isoString(from: now)

        for (index, line) in frontmatter.enumerated() {
            guard let (key, indent) = parseKey(from: line) else { continue }
            switch key {
            case "status":
                sawStatus = true
                statusIndex = index
                if let newStatus {
                    frontmatter[index] = "\(indent)status: \(newStatus.rawValue)"
                }
            case "order":
                sawOrder = true
                switch newOrder {
                case .keep:
                    break
                case .set(.some(let value)):
                    frontmatter[index] = "\(indent)order: \(formatDouble(value))"
                case .set(.none):
                    frontmatter[index] = "<<<__MUTATOR_DROP__>>>"
                }
            case "updated":
                sawUpdated = true
                frontmatter[index] = "\(indent)updated: \(nowString)"
            default:
                break
            }
        }

        if !sawUpdated {
            // Insert a fresh updated: line after status: if present, else at end.
            let line = "updated: \(nowString)"
            if let statusIndex {
                frontmatter.insert(line, at: statusIndex + 1)
            } else {
                frontmatter.append(line)
            }
        }

        if case .set(.some(let value)) = newOrder, !sawOrder {
            let line = "order: \(formatDouble(value))"
            // Re-resolve statusIndex against possibly-updated frontmatter.
            let insertAfter = frontmatter.firstIndex { line in
                parseKey(from: line)?.0 == "status"
            }
            if let insertAfter {
                frontmatter.insert(line, at: insertAfter + 1)
            } else {
                frontmatter.append(line)
            }
        }

        frontmatter.removeAll { $0 == "<<<__MUTATOR_DROP__>>>" }

        if !sawStatus, newStatus != nil {
            // Status field absent — should be unreachable for valid specs, but
            // do not silently inject it; the caller didn't ask for an arbitrary
            // location, and a malformed spec needs explicit user attention.
            throw MutatorError.noFrontmatter
        }

        var rebuilt: [String] = []
        rebuilt.append(contentsOf: lines[0...frontStart])
        rebuilt.append(contentsOf: frontmatter)
        rebuilt.append(contentsOf: lines[frontEnd..<lines.count])

        return rebuilt.joined(separator: lineSeparator)
    }

    private static func firstDelimiterIndex(in lines: [String]) -> Int? {
        for (index, line) in lines.enumerated() {
            if isDelimiter(line) { return index }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        }
        return nil
    }

    private static func secondDelimiterIndex(in lines: [String], after start: Int) -> Int? {
        guard start + 1 < lines.count else { return nil }
        for index in (start + 1)..<lines.count where isDelimiter(lines[index]) {
            return index
        }
        return nil
    }

    private static func isDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    private static func parseKey(from line: String) -> (String, String)? {
        var indent = ""
        var rest = line[...]
        while let first = rest.first, first == " " || first == "\t" {
            indent.append(first)
            rest = rest.dropFirst()
        }
        guard let colonIndex = rest.firstIndex(of: ":") else { return nil }
        let key = String(rest[rest.startIndex..<colonIndex])
        let validFirst: (Character) -> Bool = { $0.isLetter || $0 == "_" }
        let validRest: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard let firstChar = key.first, validFirst(firstChar) else { return nil }
        guard key.dropFirst().allSatisfy(validRest) else { return nil }
        return (key, indent)
    }

    private static func formatDouble(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int64(value))
        }
        let formatted = String(format: "%g", value)
        return formatted
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
