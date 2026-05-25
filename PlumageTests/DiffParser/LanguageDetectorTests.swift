import Foundation
import LanguageSupport
import Testing

@testable import Plumage

@Suite("LanguageDetector")
struct LanguageDetectorTests {
    @Test("swift extension → Swift configuration")
    func swiftExtension() {
        let config = LanguageDetector.configuration(forPath: "Sources/Foo.swift")
        #expect(config.name == "Swift")
    }

    @Test("markdown extension → Markdown configuration")
    func markdownExtension() {
        let configMD = LanguageDetector.configuration(forPath: "README.md")
        let configMarkdown = LanguageDetector.configuration(forPath: "doc.markdown")
        #expect(configMD.name == "Markdown")
        #expect(configMarkdown.name == "Markdown")
    }

    @Test("json extension → JSON configuration")
    func jsonExtension() {
        let config = LanguageDetector.configuration(forPath: "config.json")
        #expect(config.name == "JSON")
    }

    @Test("unknown extension → Plain fallback")
    func unknownExtension() {
        let config = LanguageDetector.configuration(forPath: "noext")
        #expect(config.name == "Text")
        let txt = LanguageDetector.configuration(forPath: "notes.txt")
        #expect(txt.name == "Text")
    }

    @Test("case-insensitive extension match")
    func caseInsensitive() {
        let config = LanguageDetector.configuration(forPath: "Foo.SWIFT")
        #expect(config.name == "Swift")
    }
}
