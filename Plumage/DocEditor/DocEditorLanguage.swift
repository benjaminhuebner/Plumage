import Foundation
import LanguageSupport

enum DocEditorLanguage {
    static func configuration(for url: URL) -> LanguageConfiguration {
        // The extension-to-language mapping lives in LanguageDetector; the
        // editor only adds the plain-text fallback (CodeEditor wants a
        // named config, not `.none`).
        let detected = LanguageDetector.configuration(forPath: url.path)
        return detected.name == LanguageConfiguration.none.name ? plain() : detected
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
