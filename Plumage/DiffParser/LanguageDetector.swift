import Foundation
import LanguageSupport
import RegexBuilder

nonisolated public enum LanguageDetector {
    public static func configuration(forPath path: String) -> LanguageConfiguration {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":
            return .swift()
        case "md", "markdown":
            return markdown()
        case "json":
            return json()
        default:
            return .none
        }
    }

    // Tokeniser is nil when the language configuration has no regex slots
    // populated (i.e. plain text). The body-line tokenisation path treats nil
    // identically to "no tokens" and produces an empty span list.
    static func tokeniser(forPath path: String) -> LanguageConfiguration.Tokeniser? {
        LanguageConfiguration.Tokeniser(for: configuration(forPath: path).tokenDictionary)
    }

    // Duplicated from `Plumage/SpecEditor/LanguageConfiguration+Markdown.swift`
    // and `Plumage/DocEditor/DocEditorLanguage.swift`. Third caller — by
    // rule-of-three (decisions.md 2026-05-20 #00030 LineBuffer precedent)
    // extraction to a shared language-config module is the next step. Kept
    // private here so the public surface stays a single entry point.
    private static func markdown() -> LanguageConfiguration {
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

    private static func json() -> LanguageConfiguration {
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
