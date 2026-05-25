import Foundation
import LanguageSupport

nonisolated public enum LanguageDetector {
    public static func configuration(forPath path: String) -> LanguageConfiguration {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":
            return .swift()
        case "md", "markdown":
            return .markdown()
        case "json":
            return .json()
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
}
