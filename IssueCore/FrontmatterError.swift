import Foundation

nonisolated enum FrontmatterError: Error, Sendable, Equatable {
    case missingFrontmatter
    case invalidYAML(line: Int?, message: String)
    case missingRequiredField(name: String)
    case invalidEnumValue(field: String, value: String)
    case invalidDate(field: String, value: String)
}
