import LanguageSupport
import RegexBuilder

extension LanguageConfiguration {
    nonisolated static func json() -> LanguageConfiguration {
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
        // `\.` matches any single escape (covers \", \\, \n, \t, \uXXXX) — must
        // come BEFORE the non-quote-non-backslash alternative so trailing-
        // backslash strings like "C:\\" still terminate correctly.
        return LanguageConfiguration(
            name: "JSON",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            stringRegex: #/"(?:\\.|[^"\\])*"/#,
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
