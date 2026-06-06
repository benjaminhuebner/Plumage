import Foundation
import Testing

@testable import Plumage

@Suite("GitignoreComposer")
struct GitignoreComposerTests {
    private let composer = GitignoreComposer(
        overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: nil))

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

    @Test("Every kind always includes the plumage block")
    func plumageAlways() throws {
        for kind in ProjectKind.allCases {
            let out = try composer.compose(for: kind)
            #expect(out.contains("*.plumage/runs/"), "plumage runs pattern missing for \(kind)")
            #expect(out.contains("*.plumage/sessions/"), "plumage sessions pattern missing for \(kind)")
        }
    }

    @Test("An overridden fragment flows in; other fragments fall back to bundled")
    func overriddenFragmentComposes() throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "GitignoreOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        let swiftOverride = overrideRoot.appending(path: "templates/gitignore/swift.gitignore")
        try fm.createDirectory(
            at: swiftOverride.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "MY_SWIFT_IGNORE\n".write(to: swiftOverride, atomically: true, encoding: .utf8)

        let composer = GitignoreComposer(
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: overrideRoot))
        let out = try composer.compose(for: .macOS)

        #expect(out.contains("MY_SWIFT_IGNORE"))  // overridden swift fragment
        #expect(!out.contains(".build/"))  // original swift fragment gone
        #expect(out.contains(".DS_Store"))  // macos fragment still bundled
        #expect(out.contains("DerivedData/"))  // xcode fragment still bundled
    }
}
