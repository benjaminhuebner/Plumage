import Foundation

extension FrontmatterError {
    var summary: String {
        switch self {
        case .missingFrontmatter:
            "No --- frontmatter block found"
        case .unreadable:
            "spec.md could not be read"
        case .invalidYAML(let line?, let column?, _):
            "YAML error at line \(line), column \(column)"
        case .invalidYAML(let line?, nil, _):
            "YAML error at line \(line)"
        case .invalidYAML(nil, _, _):
            "Invalid YAML in frontmatter"
        case .missingRequiredField(let name):
            "Missing required field: \(name)"
        case .invalidFieldType(let field, _):
            "Invalid type for field: \(field)"
        case .invalidEnumValue(let field, let value):
            "Unknown \(field): '\(value)'"
        case .invalidDate(let field, let value):
            "Invalid date in \(field): '\(value)'"
        }
    }

    var description: String {
        switch self {
        case .missingFrontmatter:
            """
            No --- frontmatter block found.
            spec.md must start with a YAML frontmatter delimited by --- on its own line, \
            and a closing --- before the body.
            """
        case .unreadable(let message):
            "spec.md could not be read: \(message)"
        case .invalidYAML(let line?, let column?, let message):
            "YAML error at line \(line), column \(column): \(message)"
        case .invalidYAML(let line?, nil, let message):
            "YAML error at line \(line): \(message)"
        case .invalidYAML(nil, _, let message):
            "Invalid YAML in frontmatter: \(message)"
        case .missingRequiredField(let name):
            "Missing required field: \(name)\nRequired: id, title, type, status, created, updated, branch."
        case .invalidFieldType(let field, let message):
            "Invalid type for field '\(field)': \(message)"
        case .invalidEnumValue(let field, let value):
            "Unknown \(field): '\(value)'\nAllowed: \(allowedValues(for: field))"
        case .invalidDate(let field, let value):
            "Invalid date in \(field): '\(value)'\nExpected ISO-8601, e.g. 2026-05-12T09:00:00Z."
        }
    }

    private func allowedValues(for field: String) -> String {
        switch field {
        case "type": IssueType.allCases.map(\.rawValue).joined(separator: ", ")
        case "status": IssueStatus.allCases.map(\.rawValue).joined(separator: ", ")
        default: "(unknown field)"
        }
    }
}
