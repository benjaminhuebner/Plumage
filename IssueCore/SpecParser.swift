import Foundation
import Yams

nonisolated enum SpecParser {
    // Returns the frontmatter error if parsing fails, otherwise nil. Used
    // by callers that only need validation, not the parsed Issue value —
    // avoids the Issue allocation that `parse(content:folderName:)` does
    // on the success path.
    static func validate(content: String) -> FrontmatterError? {
        switch parse(content: content, folderName: "") {
        case .success: nil
        case .failure(let error): error
        }
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
                model: raw.model
            )
        )
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

    // ISO8601DateFormatter is thread-safe for reading once configured; the
    // closures here run once, after which `formatOptions` is never mutated.
    nonisolated(unsafe) private static let plainDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date? {
        if let date = plainDateFormatter.date(from: string) { return date }
        return fractionalDateFormatter.date(from: string)
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
}
