import Foundation
import Yams

nonisolated enum SpecParser {
    // YAMLDecoder source review (Yams 5.4 Decoder.swift): decode(_:from:) builds
    // a fresh Parser + _Decoder per call and only reads the immutable `options`
    // value, which we never mutate after init. Hoisting to a shared instance
    // saves a per-call allocation in the keystroke-frequent validate() path.
    // nonisolated(unsafe) is sound and parallels the formatter caches below.
    // See notes.md #00009-yams-thread-safety.
    nonisolated(unsafe) private static let sharedDecoder = YAMLDecoder()

    // Public hook so SpecEditorModel can skip validate() entirely when the
    // frontmatter substring hasn't changed across keystrokes (the body
    // changes far more often than the frontmatter does). Returns the
    // extracted frontmatter region or nil if absent.
    static func extractFrontmatterRegion(from content: String) -> String? {
        extractFrontmatter(from: content)
    }

    // Returns the frontmatter error if parsing fails, otherwise nil. Used
    // by callers that only need validation, not the parsed Issue value —
    // SpecEditorModel calls this on every keystroke, so it skips the
    // Issue allocation (and the unused `extractGoal` walk) that
    // `parse(content:folderName:)` does on the success path.
    static func validate(content: String) -> FrontmatterError? {
        guard let yaml = extractFrontmatter(from: content) else {
            return .missingFrontmatter
        }
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingRequiredField(name: "id")
        }

        let raw: RawFrontmatter
        do {
            raw = try sharedDecoder.decode(RawFrontmatter.self, from: yaml)
        } catch let yamlError as YamlError {
            return mapYamlError(yamlError)
        } catch let decoding as DecodingError {
            return mapDecodingError(decoding)
        } catch {
            return .invalidYAML(line: nil, column: nil, message: error.localizedDescription)
        }

        if IssueType(rawValue: raw.type) == nil {
            return .invalidEnumValue(field: "type", value: raw.type)
        }
        if IssueStatus(rawValue: raw.status) == nil {
            return .invalidEnumValue(field: "status", value: raw.status)
        }
        if parseDate(raw.created) == nil {
            return .invalidDate(field: "created", value: raw.created)
        }
        if parseDate(raw.updated) == nil {
            return .invalidDate(field: "updated", value: raw.updated)
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
            raw = try sharedDecoder.decode(RawFrontmatter.self, from: yaml)
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
                model: raw.model,
                order: raw.order,
                goal: extractGoal(from: content)
            )
        )
    }

    static func extractGoal(from content: String) -> String? {
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
        var collected: [Substring] = []
        var sawOpener = false
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !sawOpener {
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

    // ISO8601DateFormatter is documented thread-safe for parsing (Foundation
    // formatters' reentrancy guarantee covers the ISO8601 variant; the
    // older "not thread-safe" caveat applies to DateFormatter's
    // locale-sensitive paths). Sharing two pre-configured instances avoids
    // a per-call allocation on every Issue parse — SpecEditorModel runs
    // this on each keystroke. `nonisolated(unsafe)` is sound: formatOptions
    // are set once at file-scope and never mutated.
    nonisolated(unsafe) private static let plainParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        return parser
    }()

    nonisolated(unsafe) private static let fractionalParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()

    private static func parseDate(_ string: String) -> Date? {
        if let date = plainParser.date(from: string) { return date }
        return fractionalParser.date(from: string)
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
            // unwrap once to recover line/column. See notes.md (#00004-frontmatter-errors).
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
    let model: String?
    let order: Double?
}
