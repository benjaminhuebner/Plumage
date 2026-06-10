import LanguageSupport

extension LanguageConfiguration {
    nonisolated static func markdown() -> LanguageConfiguration {
        LanguageConfiguration(
            name: "Markdown",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: false,
            stringRegex: #/`[^`\n]+`/#,
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
