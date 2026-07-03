import Foundation

nonisolated enum ReviewFindingsParseError: Error, Sendable, Equatable {
    case unreadable(message: String)
    case invalidJSON(message: String)
    case missingRequiredField(name: String)
    case invalidFieldValue(field: String, message: String)
}

extension ReviewFindingsParseError {
    var summary: String {
        switch self {
        case .unreadable:
            "review-findings.json could not be read"
        case .invalidJSON:
            "review-findings.json is not valid JSON"
        case .missingRequiredField(let name):
            "Missing required field: \(name)"
        case .invalidFieldValue(let field, _):
            "Invalid value for field: \(field)"
        }
    }
}
