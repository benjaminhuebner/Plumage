import Foundation
import LanguageSupport

nonisolated enum FrontmatterMessageMap {
    static func message(for error: FrontmatterError) -> TextLocated<Message> {
        let (line, column) = location(for: error)
        let message = Message(
            category: .error,
            length: 1,
            summary: error.summary,
            description: AttributedString(error.description)
        )
        return TextLocated(
            location: TextLocation(oneBasedLine: line, column: column),
            entity: message
        )
    }

    static func location(for error: FrontmatterError) -> (line: Int, column: Int) {
        switch error {
        case .invalidYAML(let line?, let column?, _):
            (line, column)
        case .invalidYAML(let line?, nil, _):
            (line, 1)
        case .invalidYAML(nil, _, _):
            (1, 1)
        case .missingFrontmatter:
            (1, 1)
        case .unreadable:
            (1, 1)
        case .missingRequiredField, .invalidFieldType, .invalidEnumValue, .invalidDate:
            (2, 1)
        }
    }
}
