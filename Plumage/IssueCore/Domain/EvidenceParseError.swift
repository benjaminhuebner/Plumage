import Foundation

nonisolated enum EvidenceParseError: Error, Sendable, Equatable {
    case unreadable(message: String)
    case invalidJSON(message: String)
    case missingRequiredField(name: String)
    case invalidFieldValue(field: String, message: String)
}

extension EvidenceParseError {
    var summary: String {
        switch self {
        case .unreadable:
            "evidence.json could not be read"
        case .invalidJSON:
            "evidence.json is not valid JSON"
        case .missingRequiredField(let name):
            "Missing required field: \(name)"
        case .invalidFieldValue(let field, _):
            "Invalid value for field: \(field)"
        }
    }
}
