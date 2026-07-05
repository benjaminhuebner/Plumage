import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeMdComposer")
struct ClaudeMdComposerTests {
    private let composer = ClaudeMdComposer(
        overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: nil))

    private func compose(
        _ kind: ProjectKind, name: String = "Acme", tagline: String = "A tiny thing"
    ) throws -> ClaudeMdComposer.Output {
        try composer.compose(
            spec: NewProjectSpec(
                kind: kind, name: name, tagline: tagline,
                projectDirectory: URL(filePath: "/tmp/x")))
    }

    @Test("macOS composes Apple + Swift sections with nested tokens resolved")
    func macOS() throws {
        let out = try compose(.macOS, name: "Acme", tagline: "A native thing")
        let md = out.claudeMd
        #expect(md.contains("# Acme"))
        #expect(md.contains("A native thing"))
        #expect(md.contains("Strict concurrency is on"))  // swift-shared CONVENTIONS
        #expect(md.contains("@Observable"))  // apple-shared CONVENTIONS
        #expect(md.contains("custom NSWindow chrome"))  // macos CONVENTIONS (AppKit)
        #expect(md.contains("Liquid Glass"))  // apple-shared PITFALLS
        #expect(md.contains("Swift Testing"))  // swift-shared BUILD AND TEST
        #expect(md.contains("xcrun mcpbridge"))  // nested <<<XCODE_MCP_LINE>>> resolved
        #expect(md.contains("DerivedData/SWBBuildService"))  // apple-shared BUILD_AND_TEST (serial rule)
        #expect(md.contains("squash-merged"))  // base skeleton merge etiquette
        #expect(!md.contains("<<<"))  // no unresolved tokens
    }

    @Test("Vapor composes server sections, no Apple content")
    func vapor() throws {
        let out = try compose(.vapor)
        let md = out.claudeMd
        #expect(md.contains("Sources/App"))  // vapor LAYOUT
        #expect(md.contains("Fluent"))  // vapor CONVENTIONS
        #expect(!md.contains("Liquid Glass"))
        #expect(!md.contains("<<<"))
    }

    @Test(".other has no layers: no Swift/Apple content, empty section headings dropped")
    func other() throws {
        let out = try compose(.other)
        let md = out.claudeMd
        #expect(!md.contains("Liquid Glass"))
        #expect(!md.contains("Sendable"))
        #expect(!md.contains("@Observable"))
        #expect(!md.contains("<<<"))
        #expect(md.contains("Describe your stack"))  // stack summary placeholder present
        #expect(!md.contains("## Conventions"))  // empty section heading dropped
        #expect(!md.contains("## Common pitfalls"))
        #expect(md.contains("## Coding defaults"))  // static section survives
        #expect(md.contains("squash-merged"))  // base etiquette present without any layer
        #expect(md.contains("Pick the simplest design that works"))
    }

    @Test("Every kind renders without leftover tokens or section markers")
    func allKindsClean() throws {
        for kind in ProjectKind.allCases {
            let out = try compose(kind)
            #expect(!out.claudeMd.contains("<<<"), "unresolved token in \(kind)")
            #expect(!out.claudeMd.contains("%%"), "leftover section marker in \(kind)")
        }
    }

    @Test("An overridden layer flows into the composed output; other files fall back to bundled")
    func overriddenLayerComposes() throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "ComposerOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        let macosOverride = overrideRoot.appending(path: "templates/macos/CLAUDE.md")
        try fm.createDirectory(
            at: macosOverride.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "%% CONVENTIONS %%\nOVERRIDE_MARKER_XYZ\n%% /CONVENTIONS %%\n".write(
            to: macosOverride, atomically: true, encoding: .utf8)

        let composer = ClaudeMdComposer(
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: overrideRoot))
        let out = try composer.compose(
            spec: NewProjectSpec(
                kind: .macOS, name: "Acme", tagline: "tl", projectDirectory: URL(filePath: "/tmp/x")))

        #expect(out.claudeMd.contains("OVERRIDE_MARKER_XYZ"))  // overridden macos layer
        #expect(!out.claudeMd.contains("custom NSWindow chrome"))  // original macos content gone
        #expect(out.claudeMd.contains("Strict concurrency is on"))  // swift-shared still bundled
        #expect(!out.claudeMd.contains("<<<"))
    }

    @Test("A legacy layer block lands under the migrated skeleton's custom heading")
    func legacyBlockFollowsMigratedSkeletonHeading() throws {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "ComposerOverride-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: overrideRoot) }
        // Skeleton already migrated (heading kept, placeholder gone); the layer is legacy.
        for (rel, contents) in [
            ("templates/CLAUDE.md", "# <<<PROJECT_NAME>>>\n\n## Custom\n"),
            ("templates/macos/CLAUDE.md", "%% CUSTOM %%\n- custom note\n%% /CUSTOM %%\n"),
        ] {
            let url = overrideRoot.appending(path: rel)
            try fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        let composer = ClaudeMdComposer(
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: overrideRoot))
        let out = try composer.compose(
            spec: NewProjectSpec(
                kind: .macOS, name: "Acme", tagline: "tl", projectDirectory: URL(filePath: "/tmp/x")))

        #expect(out.claudeMd.contains("## Custom\n- custom note"))
        #expect(!out.claudeMd.contains("## CUSTOM"))
    }
}
