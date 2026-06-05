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

nonisolated struct FrontmatterMutation: Sendable {
    var title: SetValue<String> = .keep
    var type: SetValue<IssueType> = .keep
    var status: SetValue<IssueStatus> = .keep
    var order: SetValue<Double?> = .keep
    var labels: SetValue<[String]> = .keep
    // Body splice is done in the same single write as the frontmatter
    // mutation so saveBody can't leave the file with a new body but a
    // stale `updated:` stamp on partial failure.
    var body: SetValue<String> = .keep
}

nonisolated enum FrontmatterMutator {
    static func mutate(
        specURL: URL,
        mutation: FrontmatterMutation,
        now: Date
    ) throws {
        let content = try String(contentsOf: specURL, encoding: .utf8)
        let updated = try transform(content: content, mutation: mutation, now: now)
        try SpecWriter.write(updated, to: specURL)
    }

    static func transform(
        content: String,
        mutation: FrontmatterMutation,
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
        var sawTitle = false
        var sawType = false
        var sawStatus = false
        var sawOrder = false
        var sawLabels = false
        var sawUpdated = false
        var statusIndex: Int?

        let nowString = isoString(from: now)

        for (index, line) in frontmatter.enumerated() {
            guard let (key, indent) = parseKey(from: line) else { continue }
            switch key {
            case "title":
                sawTitle = true
                if case .set(let value) = mutation.title {
                    frontmatter[index] = "\(indent)title: \(formatTitleValue(value))"
                }
            case "type":
                sawType = true
                if case .set(let value) = mutation.type {
                    frontmatter[index] = "\(indent)type: \(value.rawValue)"
                }
            case "status":
                sawStatus = true
                statusIndex = index
                if case .set(let value) = mutation.status {
                    frontmatter[index] = "\(indent)status: \(value.rawValue)"
                }
            case "order":
                sawOrder = true
                switch mutation.order {
                case .keep:
                    break
                case .set(.some(let value)):
                    frontmatter[index] = "\(indent)order: \(formatDouble(value))"
                case .set(.none):
                    frontmatter[index] = "<<<__MUTATOR_DROP__>>>"
                }
            case "labels":
                sawLabels = true
                if case .set(let value) = mutation.labels {
                    frontmatter[index] = "\(indent)labels: \(formatLabels(value))"
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

        if case .set(.some(let value)) = mutation.order, !sawOrder {
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

        // Status-field absent and caller asked to set it: malformed spec
        // needs explicit user attention rather than silent injection.
        if !sawStatus, case .set = mutation.status {
            throw MutatorError.noFrontmatter
        }
        // Same for the other fields the form can mutate.
        if !sawTitle, case .set = mutation.title {
            throw MutatorError.noFrontmatter
        }
        if !sawType, case .set = mutation.type {
            throw MutatorError.noFrontmatter
        }
        if !sawLabels, case .set = mutation.labels {
            throw MutatorError.noFrontmatter
        }

        var rebuilt: [String] = []
        rebuilt.append(contentsOf: lines[0...frontStart])
        rebuilt.append(contentsOf: frontmatter)

        switch mutation.body {
        case .keep:
            rebuilt.append(contentsOf: lines[frontEnd..<lines.count])
            return rebuilt.joined(separator: lineSeparator)
        case .set(let newBody):
            // Preserve the closing `---` line itself, then a single blank
            // separator, then the new body. Matches the convention in
            // existing spec files and what IssueDetailModel.replaceBody used
            // to produce.
            rebuilt.append(lines[frontEnd])
            let frontmatterSection = rebuilt.joined(separator: lineSeparator)
            return frontmatterSection + lineSeparator + lineSeparator + newBody
        }
    }

    // Drop-path back-compat wrapper. ProjectKanbanModel's Mutator typealias
    // pins this exact signature; keep it green so #00015 callers compile
    // unchanged. Internally routes through the new mutation entry point.
    static func mutate(
        specURL: URL,
        newStatus: IssueStatus?,
        newOrder: SetValue<Double?>,
        now: Date
    ) throws {
        var mutation = FrontmatterMutation()
        if let newStatus { mutation.status = .set(newStatus) }
        mutation.order = newOrder
        try mutate(specURL: specURL, mutation: mutation, now: now)
    }

    static func transform(
        content: String,
        newStatus: IssueStatus?,
        newOrder: SetValue<Double?>,
        now: Date
    ) throws -> String {
        var mutation = FrontmatterMutation()
        if let newStatus { mutation.status = .set(newStatus) }
        mutation.order = newOrder
        return try transform(content: content, mutation: mutation, now: now)
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

    static func formatTitleValue(_ raw: String) -> String {
        if needsYAMLQuoting(raw) {
            let escaped =
                raw
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return raw
    }

    static func formatLabels(_ labels: [String]) -> String {
        let formatted = labels.map { formatLabelValue($0) }
        return "[\(formatted.joined(separator: ", "))]"
    }

    private static func formatLabelValue(_ raw: String) -> String {
        if needsYAMLQuoting(raw) {
            let escaped =
                raw
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return raw
    }

    private static let dangerCharacters: Set<Character> = [
        ":", "#", "&", "*", "!", "|", ">", "%", "@", "\"", "\\", "{", "}", "[", "]", ",", "?",
    ]

    private static func needsYAMLQuoting(_ raw: String) -> Bool {
        guard let first = raw.first else { return true }
        // Leading whitespace or `-` would be parsed as a list/scalar marker.
        if first == " " || first == "\t" || first == "-" { return true }
        return raw.contains { dangerCharacters.contains($0) }
    }

    private static func isoString(from date: Date) -> String {
        ISO8601Flexible.string(from: date)
    }
}
