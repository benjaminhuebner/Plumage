import Foundation
import Yams

nonisolated enum SpecParser {
    static func parse(content: String, folder: String) -> Result<Issue, FrontmatterError> {
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
            return .failure(.invalidYAML(line: nil, message: error.localizedDescription))
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
                folder: folder,
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
        var lines = content.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        lines.removeFirst()
        guard let closingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return nil
        }
        return lines[..<closingIndex].joined(separator: "\n")
    }

    private static func parseDate(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    private static func mapYamlError(_ error: YamlError) -> FrontmatterError {
        switch error {
        case .scanner(_, let problem, let mark, _),
            .parser(_, let problem, let mark, _),
            .composer(_, let problem, let mark, _):
            .invalidYAML(line: mark.line, message: problem)
        case .reader(let problem, _, _, _):
            .invalidYAML(line: nil, message: problem)
        default:
            .invalidYAML(line: nil, message: error.localizedDescription)
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
                .invalidYAML(line: nil, message: context.debugDescription)
            }
        @unknown default:
            .invalidYAML(line: nil, message: error.localizedDescription)
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
