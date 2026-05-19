import Foundation
import LanguageSupport

enum DocEditorLanguage {
    static func configuration(for url: URL) -> LanguageConfiguration {
        switch url.pathExtension.lowercased() {
        case "md":
            return LanguageConfiguration.markdown()
        default:
            return plain()
        }
    }

    private static func plain() -> LanguageConfiguration {
        LanguageConfiguration(
            name: "Plain",
            supportsSquareBrackets: false,
            supportsCurlyBrackets: false,
            stringRegex: nil,
            characterRegex: nil,
            numberRegex: nil,
            singleLineComment: nil,
            nestedComment: nil,
            identifierRegex: nil,
            operatorRegex: nil,
            reservedIdentifiers: [],
            reservedOperators: []
        )
    }
}
