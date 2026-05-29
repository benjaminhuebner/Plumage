import Foundation
import Testing

@testable import Plumage

@Suite("GitignoreComposer")
struct GitignoreComposerTests {
    private let composer = GitignoreComposer(
        fragmentsDir: RepoAssets.templatesDir.appending(path: "gitignore", directoryHint: .isDirectory))

    @Test("macOS gets Swift + Xcode + macOS blocks")
    func macOS() throws {
        let out = try composer.compose(for: .macOS)
        #expect(out.contains("DerivedData/"))  // xcode
        #expect(out.contains(".build/"))  // swift
        #expect(out.contains(".DS_Store"))  // macos
    }

    @Test("Vapor gets Swift + macOS, no Xcode block")
    func vapor() throws {
        let out = try composer.compose(for: .vapor)
        #expect(out.contains(".build/"))  // swift
        #expect(out.contains(".DS_Store"))  // macos
        #expect(!out.contains("xcuserdata"))  // no xcode tag
    }

    @Test(".other gets only the macOS block")
    func other() throws {
        let out = try composer.compose(for: .other)
        #expect(out.contains(".DS_Store"))  // macos
        #expect(!out.contains(".build/"))  // no swift tag
        #expect(!out.contains("DerivedData/"))  // no xcode tag
    }

    @Test("Every kind always includes the macOS block")
    func macOSAlways() throws {
        for kind in ProjectKind.allCases {
            #expect(try composer.compose(for: kind).contains(".DS_Store"), "macOS block missing for \(kind)")
        }
    }
}
