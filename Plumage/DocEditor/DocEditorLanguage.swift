import Foundation
import LanguageSupport
import RegexBuilder

enum DocEditorLanguage {
    static func configuration(for url: URL) -> LanguageConfiguration {
        switch url.pathExtension.lowercased() {
        case "md":
            return LanguageConfiguration.markdown()
        case "json":
            return json()
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

    // Minimal JSON config — strings, numbers, brackets, and the three reserved
    // literals. Standard JSON has no comments; JSONC files would need a
    // separate variant.
    private static func json() -> LanguageConfiguration {
        // RFC 8259 number form: optional minus, integer (0 or 1-9 digits),
        // optional fraction, optional exponent.
        let numberRegex: Regex<Substring> = Regex {
            Optionally { "-" }
            ChoiceOf {
                "0"
                Regex {
                    ("1"..."9")
                    ZeroOrMore { ("0"..."9") }
                }
            }
            Optionally {
                Regex {
                    "."
                    OneOrMore { ("0"..."9") }
                }
            }
            Optionally {
                Regex {
                    CharacterClass.anyOf("eE")
                    Optionally { CharacterClass.anyOf("+-") }
                    OneOrMore { ("0"..."9") }
                }
            }
        }
        return LanguageConfiguration(
            name: "JSON",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            stringRegex: /\"(?:\\\"|[^\"])*+\"/,
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: nil,
            nestedComment: nil,
            identifierRegex: nil,
            operatorRegex: nil,
            reservedIdentifiers: ["true", "false", "null"],
            reservedOperators: [":", ","]
        )
    }
}
