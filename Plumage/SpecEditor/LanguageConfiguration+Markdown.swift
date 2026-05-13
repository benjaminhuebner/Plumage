import LanguageSupport

extension LanguageConfiguration {
    static func markdown() -> LanguageConfiguration {
        LanguageConfiguration(
            name: "Markdown",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: false,
            stringRegex: try? Regex<Substring>(#"`[^`\n]+`"#, as: Substring.self),
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
