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

    @Test("composedLooseFiles: the template root wins a name clash over a member component (#00084)")
    func composedLooseFilesTemplateWinsClash() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BASE", to: tree.override, rel: "docs/x.md")
        try write("COMP", to: tree.override, rel: "components/c1/docs/x.md")
        try write("TMPL", to: tree.override, rel: "templates/t1/docs/x.md")
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        // Roots in precedence order: base, member component, template (template last = wins).
        let composed = overrides.composedLooseFiles(category: "docs", roots: ["", "components/c1", "templates/t1"])
        let winner = try #require(composed.first { $0.name == "x.md" })
        #expect(winner.relativePath == "templates/t1/docs/x.md")
    }

    @Test("composedArbitraryFiles reproduces a real .claude/ loose file (#00084)")
    func composedArbitraryFilesIncludesClaude() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("X", to: tree.override, rel: ".claude/bla.md")
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        let composed = overrides.composedArbitraryFiles(roots: [""])
        #expect(composed.contains { $0.output == ".claude/bla.md" && $0.relativePath == ".claude/bla.md" })
    }

    @Test("resolveLooseFile merges a placeholder skeleton with a later layer's block")
    func resolveLooseFilePlaceholderMerge() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        // Base skeleton carries a `<<<refs>>>` placeholder; the template layer fills it.
        try write("# Doc\n\n## Refs\n<<<refs>>>\n", to: tree.override, rel: "docs/x.md")
        try write("%% refs %%\n- one\n- two\n%% /refs %%\n", to: tree.override, rel: "templates/t1/docs/x.md")
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)

        let variants = try #require(
            overrides.composedLooseFileVariants(category: "docs", roots: ["", "templates/t1"])
                .first { $0.name == "x.md" }?.variants)
        #expect(variants == ["docs/x.md", "templates/t1/docs/x.md"])

        guard case .merged(let data) = try overrides.resolveLooseFile(variants: variants) else {
            Issue.record("expected a merged placeholder result")
            return
        }
        #expect(String(decoding: data, as: UTF8.self) == "# Doc\n\n## Refs\n- one\n- two\n")
    }

    @Test("resolveLooseFile keeps the file-level winner when the skeleton has no placeholder")
    func resolveLooseFileNoPlaceholderKeepsWinner() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BASE", to: tree.override, rel: "docs/x.md")
        try write("TMPL", to: tree.override, rel: "templates/t1/docs/x.md")
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)

        let variants = try #require(
            overrides.composedLooseFileVariants(category: "docs", roots: ["", "templates/t1"])
                .first { $0.name == "x.md" }?.variants)
        guard case .copy(let url) = try overrides.resolveLooseFile(variants: variants) else {
            Issue.record("expected a file-level copy result")
            return
        }
        #expect(url == overrides.url(forRelative: "templates/t1/docs/x.md"))
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

    // MARK: - Write path

    @Test("writeOverride materializes the slot and wins over bundled")
    func writeOverrideWins() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BUNDLED", to: tree.bundled, rel: "templates/macos.md")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        #expect(!overrides.hasOverride(forRelative: "templates/macos.md"))
        let written = try overrides.writeOverride("MINE", toRelative: "templates/macos.md")

        #expect(written == tree.override.appending(path: "templates/macos.md"))
        #expect(overrides.hasOverride(forRelative: "templates/macos.md"))
        #expect(try overrides.string(atRelative: "templates/macos.md") == "MINE")
    }

    @Test("removeOverride reverts a bundled-backed file to its bundled bytes")
    func removeOverrideRevertsToBundled() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BUNDLED", to: tree.bundled, rel: "templates/macos.md")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        try overrides.writeOverride("MINE", toRelative: "templates/macos.md")
        #expect(overrides.hasOverride(forRelative: "templates/macos.md"))

        try overrides.removeOverride(forRelative: "templates/macos.md")
        #expect(!overrides.hasOverride(forRelative: "templates/macos.md"))
        #expect(try overrides.string(atRelative: "templates/macos.md") == "BUNDLED")
    }

    @Test("removeOverride on an absent override is a no-op")
    func removeOverrideIdempotent() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        try overrides.removeOverride(forRelative: "templates/macos.md")
        #expect(!overrides.hasOverride(forRelative: "templates/macos.md"))
    }

    @Test("removeOverride prunes the emptied store back to byte-identity")
    func removeOverridePrunesEmptyDirectories() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        try overrides.writeOverride("X", toRelative: "skills/my-skill/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: tree.override.appending(path: "skills").path))

        try overrides.removeOverride(forRelative: "skills/my-skill/SKILL.md")
        // The whole "skills/my-skill" chain is gone; the store root survives.
        #expect(!FileManager.default.fileExists(atPath: tree.override.appending(path: "skills").path))
        #expect(FileManager.default.fileExists(atPath: tree.override.path))
    }

    @Test("hasBundledOriginal distinguishes bundled-backed from user-authored")
    func bundledOriginalDetection() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BUNDLED", to: tree.bundled, rel: "templates/macos.md")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        try overrides.writeOverride("MINE", toRelative: "templates/macos.md")
        try overrides.writeOverride("NEW", toRelative: "templates/authored.md")

        #expect(overrides.hasBundledOriginal(forRelative: "templates/macos.md"))
        #expect(!overrides.hasBundledOriginal(forRelative: "templates/authored.md"))
    }

    @Test("writeOverride without a store throws and stays bundled-identical")
    func writeWithoutStoreThrows() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("BUNDLED", to: tree.bundled, rel: "templates/macos.md")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: nil)
        #expect(throws: ScaffoldOverridesError.noOverrideStore) {
            try overrides.writeOverride("MINE", toRelative: "templates/macos.md")
        }
        #expect(try overrides.string(atRelative: "templates/macos.md") == "BUNDLED")
    }

    @Test("writeOverride rejects a path that escapes the store")
    func writeRejectsEscape() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        #expect(throws: (any Error).self) {
            try overrides.writeOverride("X", toRelative: "../escape.md")
        }
    }

    // MARK: - Noise filtering

    @Test("Recursive file enumeration drops .DS_Store, AppleDouble and .git contents")
    func recursiveWalkSkipsNoise() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("real", to: tree.override, rel: "skills/s/SKILL.md")
        try write("ref", to: tree.override, rel: "skills/s/reference.md")
        try write("junk", to: tree.override, rel: "skills/s/.DS_Store")
        try write("apple", to: tree.override, rel: "skills/s/._SKILL.md")
        try write("gitcfg", to: tree.override, rel: "skills/s/.git/config")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        #expect(overrides.overrideFileNamesRecursive(inRelativeDir: "skills/s") == ["SKILL.md", "reference.md"])
    }

    @Test("Directory enumeration skips VCS/noise directories")
    func directoryWalkSkipsNoise() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("x", to: tree.override, rel: "myfolder/keep.txt")
        try write("cfg", to: tree.override, rel: "myfolder/.git/config")

        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        let dirs = overrides.overrideDirectoryPaths()
        #expect(dirs.contains("myfolder"))
        #expect(!dirs.contains { $0.split(separator: "/").contains(".git") })
    }

    @Test("copyResolvedTree never copies macOS/VCS noise into the scaffold output")
    func copyResolvedTreeSkipsNoise() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("# Skill", to: tree.bundled, rel: "skills/demo/SKILL.md")
        try write("junk", to: tree.bundled, rel: "skills/demo/.DS_Store")
        try write("cfg", to: tree.bundled, rel: "skills/demo/.git/config")
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        let dest = tree.override.appending(path: "out", directoryHint: .isDirectory)

        try overrides.copyResolvedTree(relativeDir: "skills/demo", to: dest)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dest.appending(path: "SKILL.md").path))
        #expect(!fm.fileExists(atPath: dest.appending(path: ".DS_Store").path))
        #expect(!fm.fileExists(atPath: dest.appending(path: ".git/config").path))
    }

    @Test("Arbitrary-root-files scan skips typed dirs and surfaces nested user files")
    func arbitraryRootFiles() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("h", to: tree.override, rel: "hooks/a.sh")  // typed dir → excluded
        try write("e", to: tree.override, rel: ".editorconfig")  // root dotfile → kept
        try write("n", to: tree.override, rel: "myfolder/note.txt")  // nested arbitrary → kept
        try write("d", to: tree.override, rel: "myfolder/.DS_Store")  // noise → dropped
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)

        let files = overrides.overrideRootArbitraryFiles(excludingTopLevel: ["hooks"])
        #expect(files.contains(".editorconfig"))
        #expect(files.contains("myfolder/note.txt"))
        #expect(!files.contains { $0.hasPrefix("hooks/") })
        #expect(!files.contains { $0.contains(".DS_Store") })
    }

    // MARK: - Scope-rooted enumerators (#00078)

    @Test("Scoped skill-dir names read only inside the scope subtree")
    func scopedSkillDirNames() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("# base", to: tree.override, rel: "skills/base-skill/SKILL.md")
        try write("# t", to: tree.override, rel: "templates/t1/skills/t-skill/SKILL.md")
        try write("# c", to: tree.override, rel: "components/c1/skills/c-skill/SKILL.md")
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)

        #expect(overrides.overrideSkillDirNames() == ["base-skill"])
        #expect(overrides.overrideSkillDirNames(inRoot: "templates/t1") == ["t-skill"])
        #expect(overrides.overrideSkillDirNames(inRoot: "components/c1") == ["c-skill"])
    }

    @Test("Scoped arbitrary-files scan returns scope-relative paths inside the subtree")
    func scopedArbitraryFiles() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("r", to: tree.override, rel: ".editorconfig")  // base root → not in scope
        try write("d", to: tree.override, rel: "templates/t1/docs/x.md")  // typed → excluded
        try write("a", to: tree.override, rel: "templates/t1/note.txt")  // arbitrary → kept
        try write("n", to: tree.override, rel: "templates/t1/sub/deep.txt")  // nested → kept
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)

        let files = overrides.overrideRootArbitraryFiles(
            inRoot: "templates/t1", excludingTopLevel: ["docs", "skills", "agents"])
        #expect(files == ["note.txt", "sub/deep.txt"])  // scope-relative, no prefix, docs excluded
        #expect(!files.contains(".editorconfig"))  // base-root file not pulled into the scope
    }

    @Test("Scoped arbitrary scan honours a store-root tombstone on the full path")
    func scopedArbitraryFilesHonoursSuppression() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("a", to: tree.override, rel: "templates/t1/gone.txt")
        try write("b", to: tree.override, rel: "templates/t1/stay.txt")
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)
        try overrides.suppress(relativePath: "templates/t1/gone.txt")

        let files = overrides.overrideRootArbitraryFiles(
            inRoot: "templates/t1", excludingTopLevel: [])
        #expect(files == ["stay.txt"])
    }

    @Test("Scoped directory walk returns scope-relative folder paths")
    func scopedDirectoryPaths() throws {
        let tree = try makeTree()
        defer { tree.cleanup() }
        try write("x", to: tree.override, rel: "components/c1/myfolder/keep.txt")
        try write("y", to: tree.override, rel: "myfolder-base/keep.txt")  // base scope
        let overrides = ScaffoldOverrides(bundledRoot: tree.bundled, overrideRoot: tree.override)

        let dirs = overrides.overrideDirectoryPaths(inRoot: "components/c1")
        #expect(dirs.contains("myfolder"))  // scope-relative, no "components/c1" prefix
        #expect(!dirs.contains { $0.hasPrefix("components") })
        #expect(!dirs.contains("myfolder-base"))  // base-scope folder not in component scope
    }
}
