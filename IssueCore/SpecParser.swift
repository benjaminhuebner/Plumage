import Foundation
import Yams

nonisolated enum SpecParser {
    static func parse(content: String, folder: String) -> Issue? {
        guard let yaml = extractFrontmatter(from: content) else { return nil }
        guard let raw = try? YAMLDecoder().decode(Frontmatter.self, from: yaml) else { return nil }
        guard let created = parseDate(raw.created), let updated = parseDate(raw.updated) else { return nil }
        return Issue(
            id: raw.id,
            folder: folder,
            title: raw.title,
            type: raw.type,
            status: raw.status,
            created: created,
            updated: updated,
            branch: raw.branch,
            labels: raw.labels ?? [],
            model: raw.model
        )
    }

    private static func extractFrontmatter(from content: String) -> String? {
        var lines = content.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        lines.removeFirst()
        guard let closingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return nil
        }
        let body = lines[..<closingIndex].joined(separator: "\n")
        return body.isEmpty ? nil : body
    }

    private static func parseDate(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}

private nonisolated struct Frontmatter: Decodable {
    let id: Int
    let title: String
    let type: IssueType
    let status: IssueStatus
    let created: String
    let updated: String
    let branch: String
    let labels: [String]?
    let model: String?
}
