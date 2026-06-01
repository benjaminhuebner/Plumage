import Foundation
import Testing

@testable import Plumage

@Suite("ScaffoldOverrides")
struct ScaffoldOverridesTests {
    private func makeTree() throws -> (bundled: URL, override: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "Overrides-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = base.appending(path: "bundled", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: override, withIntermediateDirectories: true)
        return (bundled, override, { try? fm.removeItem(at: base) })
    }

    private func write(_ contents: String, to root: URL, rel: String) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("Absent override resolves to the bundled file")
    func absentFallsBackToBundled() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BUNDLED", to: tree.bundled, rel: "templates/CLAUDE.md")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        #expect(try overrides.string(atRelative: "templates/CLAUDE.md") == "BUNDLED")
        #expect(
            overrides.url(forRelative: "templates/CLAUDE.md") == tree.bundled.appending(path: "templates/CLAUDE.md"))
        #expect(!overrides.hasOverride(forRelative: "templates/CLAUDE.md"))
    }

    @Test("Present override wins over the bundled file")
    func presentOverrideWins() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BUNDLED", to: tree.bundled, rel: "templates/CLAUDE.md")
        try write("OVERRIDDEN", to: tree.override, rel: "templates/CLAUDE.md")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        #expect(try overrides.string(atRelative: "templates/CLAUDE.md") == "OVERRIDDEN")
        #expect(
            overrides.url(forRelative: "templates/CLAUDE.md") == tree.override.appending(path: "templates/CLAUDE.md"))
        #expect(overrides.hasOverride(forRelative: "templates/CLAUDE.md"))
    }

    @Test("Partial directory mixes overridden and bundled files per file")
    func partialDirectoryMix() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BASE-MACOS", to: tree.bundled, rel: "templates/macos.md")
        try write("BASE-SHARED", to: tree.bundled, rel: "templates/swift-shared.md")
        // Only override one of the two files in the same directory.
        try write("MINE-MACOS", to: tree.override, rel: "templates/macos.md")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        #expect(try overrides.string(atRelative: "templates/macos.md") == "MINE-MACOS")
        #expect(try overrides.string(atRelative: "templates/swift-shared.md") == "BASE-SHARED")
        #expect(overrides.hasOverride(forRelative: "templates/macos.md"))
        #expect(!overrides.hasOverride(forRelative: "templates/swift-shared.md"))
    }

    @Test("No override root configured always resolves bundled")
    func noOverrideRoot() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BUNDLED", to: tree.bundled, rel: "hooks/format-swift.sh")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: nil)
        #expect(try overrides.string(atRelative: "hooks/format-swift.sh") == "BUNDLED")
        #expect(overrides.overrideURL(forRelative: "hooks/format-swift.sh") == nil)
        #expect(!overrides.hasOverride(forRelative: "hooks/format-swift.sh"))
    }

    @Test("data(atRelative:) reads raw bytes through the resolver")
    func dataReads() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("xyz", to: tree.bundled, rel: "configs/swift-format")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        #expect(try overrides.data(atRelative: "configs/swift-format") == Data("xyz".utf8))
    }
}
