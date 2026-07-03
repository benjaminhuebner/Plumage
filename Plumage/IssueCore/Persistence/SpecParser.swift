import Foundation
import Yams

nonisolated enum SpecParser {
    // folderName only lands on the parsed Issue, never in an error, so
    // parse's failure surface doubles as the validation result.
    static func validate(content: String) -> FrontmatterError? {
        if case .failure(let error) = parse(content: content, folderName: "") {
            return error
        }
        return nil
    }

    static func parse(content: String, folderName: String) -> Result<Issue, FrontmatterError> {
        guard let yaml = extractFrontmatter(from: content) else {
            return .failure(.missingFrontmatter)
        }
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.missingRequiredField(name: "id"))
        }

        let raw: RawFrontmatter
        do {
            // A fresh decoder per call: YAMLDecoder init is allocation-only and
            // decode builds its own Parser, so there is no shared mutable state
            // to reason about across concurrent discovery tasks.
            raw = try YAMLDecoder().decode(RawFrontmatter.self, from: yaml)
        } catch let yamlError as YamlError {
            return .failure(mapYamlError(yamlError))
        } catch let decoding as DecodingError {
            return .failure(mapDecodingError(decoding))
        } catch {
            return .failure(.invalidYAML(line: nil, column: nil, message: error.localizedDescription))
        }

        guard let type = IssueType(rawValue: raw.type) else {
            return .failure(.invalidEnumValue(field: "type", value: raw.type))
        }
        guard let status = IssueStatus(rawValue: raw.status) else {
            return .failure(.invalidEnumValue(field: "status", value: raw.status))
        }
        guard let created = parseDate(raw.created) else {
            return .failure(.invalidDate(field: "created", value: raw.created))
        }
        guard let updated = parseDate(raw.updated) else {
            return .failure(.invalidDate(field: "updated", value: raw.updated))
        }

        return .success(
            Issue(
                id: raw.id,
                folderName: folderName,
                title: raw.title,
                type: type,
                status: status,
                created: created,
                updated: updated,
                branch: raw.branch,
                labels: raw.labels ?? [],
                blockedBy: raw.blockedBy ?? [],
                mergeSubject: raw.mergeSubject,
                order: raw.order,
                goal: extractGoal(from: content)
            )
        )
    }

    static func extractBody(from content: String) -> String {
        // Split on the second `---` line: frontmatter is dropped, everything after
        // is the body (including embedded `---` lines). CRLF is normalized first so
        // raw file content from any platform is safe.
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var seen = 0
        var bodyStart = 0
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                seen += 1
                if seen == 2 {
                    bodyStart = index + 1
                    break
                }
            }
        }
        if seen < 2 { return "" }
        // Drop a single leading newline so users don't see a stray blank
        // line at the top of the body editor.
        if bodyStart < lines.count, lines[bodyStart].isEmpty {
            bodyStart += 1
        }
        guard bodyStart <= lines.count else { return "" }
        return lines[bodyStart..<lines.count].joined(separator: "\n")
    }

    static func extractGoal(from content: String) -> String? {
        // Cheap substring probe before the full line walk — most non-spec
        // markdown has no Goal heading at all ("# Goal" also matches "## Goal").
        guard content.contains("# Goal") else { return nil }
        let normalized =
            content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var inGoal = false
        var collected: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inGoal {
                if trimmed == "## Goal" || trimmed == "# Goal" {
                    inGoal = true
                }
                continue
            }
            if trimmed.hasPrefix("#") { break }
            collected.append(String(line))
        }
        if collected.isEmpty { return nil }

        let joined = collected.joined(separator: "\n")
        let stripped = stripHTMLComments(joined)

        var firstParagraph: [String] = []
        for line in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if firstParagraph.isEmpty { continue }
                break
            }
            firstParagraph.append(trimmed)
        }
        // Collapse runs of whitespace — stripping inline `<!-- … -->`
        // can leave double spaces between the surrounding words.
        let paragraph =
            firstParagraph
            .joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if paragraph.isEmpty { return nil }

        let cap = 240
        if paragraph.count > cap {
            let prefix = paragraph.prefix(cap).trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix + "…"
        }
        return paragraph
    }

    private static func stripHTMLComments(_ input: String) -> String {
        var result = ""
        var index = input.startIndex
        while index < input.endIndex {
            guard let openRange = input.range(of: "<!--", range: index..<input.endIndex) else {
                result += input[index..<input.endIndex]
                break
            }
            result += input[index..<openRange.lowerBound]
            guard let closeRange = input.range(of: "-->", range: openRange.upperBound..<input.endIndex) else {
                // Unclosed comment: keep the literal text so the typo is visible
                // to the author rather than silently swallowing the rest of the section.
                result += input[openRange.lowerBound..<input.endIndex]
                break
            }
            index = closeRange.upperBound
        }
        return result
    }

    private static func extractFrontmatter(from content: String) -> String? {
        // Normalize CRLF first: splitting on "\n" leaves a trailing \r on
        // every line (the \r\n grapheme survives the split), so a CRLF file's
        // "---\r" delimiter never matched and the whole spec read as invalid.
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        var collected: [Substring] = []
        var sawOpener = false
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !sawOpener {
                // Tolerate leading blank lines, matching FrontmatterMutator's
                // delimiter search — parser and writer must agree on validity.
                if trimmed.isEmpty { continue }
                guard trimmed == "---" else { return nil }
                sawOpener = true
                continue
            }
            if trimmed == "---" {
                return collected.joined(separator: "\n")
            }
            collected.append(line)
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        ISO8601Flexible.date(from: string)
    }

    private static func mapYamlError(_ error: YamlError) -> FrontmatterError {
        switch error {
        case .scanner(_, let problem, let mark, _),
            .parser(_, let problem, let mark, _),
            .composer(_, let problem, let mark, _):
            .invalidYAML(line: mark.line, column: mark.column, message: problem)
        case .reader(let problem, _, _, _):
            .invalidYAML(line: nil, column: nil, message: problem)
        default:
            .invalidYAML(line: nil, column: nil, message: error.localizedDescription)
        }
    }

    private static func mapDecodingError(_ error: DecodingError) -> FrontmatterError {
        switch error {
        case .keyNotFound(let key, _):
            .missingRequiredField(name: key.stringValue)
        case .valueNotFound(_, let context):
            .missingRequiredField(name: context.codingPath.last?.stringValue ?? "(unknown)")
        case .typeMismatch(_, let context):
            .invalidFieldType(
                field: context.codingPath.last?.stringValue ?? "(unknown)",
                message: context.debugDescription
            )
        case .dataCorrupted(let context):
            // Yams 5.4 wraps its own scanner/parser/composer errors as DecodingError.dataCorrupted —
            // unwrap once to recover line/column.
            if let yamlErr = context.underlyingError as? YamlError {
                mapYamlError(yamlErr)
            } else {
                .invalidYAML(line: nil, column: nil, message: context.debugDescription)
            }
        @unknown default:
            .invalidYAML(line: nil, column: nil, message: error.localizedDescription)
        }
    }
}

private nonisolated struct RawFrontmatter: Decodable {
    let id: Int
    let title: String
    let type: String
    let status: String
    let created: String
    let updated: String
    let branch: String
    let labels: [String]?
    let blockedBy: [String]?
    let mergeSubject: String?
    let order: Double?
}
