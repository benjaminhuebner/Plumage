import Foundation

nonisolated enum FrontmatterError: Error, Sendable, Equatable {
    case missingFrontmatter
    case unreadable(message: String)
    case invalidYAML(line: Int?, message: String)
    case missingRequiredField(name: String)
    case invalidFieldType(field: String, message: String)
    case invalidEnumValue(field: String, value: String)
    case invalidDate(field: String, value: String)
}
