import Foundation
import Testing

@testable import Plumage

// Base editing (the Base entry is selectable and its files edit to the
// override store) is wired elsewhere. This locks the criterion that a Base
// edit reflects across templates: an override of the overarching `templates/CLAUDE.md`
// must appear in every template's composed CLAUDE.md, since the composer reads the
// base through the same override store the manager writes to.
@Suite("Base CLAUDE.md edit reflects across templates")
struct BaseEditingReflectionTests {
    private func makeOverrides() throws -> (overrides: ScaffoldOverrides, cleanup: () -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(
            path: "BaseEdit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: root),
            { try? fm.removeItem(at: root) }
        )
    }

    @Test("An override of the Base CLAUDE.md surfaces in a template's composed output")
    func baseOverrideReflects() throws {
        let context = try makeOverrides()
        defer { context.cleanup() }
        let marker = "PLUMAGE-BASE-EDIT-\(UUID().uuidString)"
        _ = try context.overrides.writeOverride(
            "# <<<PROJECT_NAME>>>\n\n\(marker)\n", toRelative: "templates/CLAUDE.md")

        let composer = ClaudeMdComposer(overrides: context.overrides)
        let output = try composer.compose(
            spec: NewProjectSpec(
                kind: .other, name: "Acme", tagline: "t",
                projectDirectory: URL(filePath: "/tmp/x")))

        #expect(output.claudeMd.contains(marker))
        #expect(output.claudeMd.contains("Acme"))
    }

    @Test("A new Base placeholder outside the old four sections is filled by a layer block")
    func arbitraryPlaceholderReflects() throws {
        let context = try makeOverrides()
        defer { context.cleanup() }
        // The manager writes both edits to the override store the composer reads from:
        // a brand-new `<<<refdocs>>>` placeholder under `## Reference docs` in the base
        // skeleton, and a matching `%% refdocs %%` block in an active layer.
        _ = try context.overrides.writeOverride(
            "# <<<PROJECT_NAME>>>\n\n## Reference docs\n<<<refdocs>>>\n",
            toRelative: "templates/CLAUDE.md")
        _ = try context.overrides.writeOverride(
            "%% refdocs %%\n- PROJECT.md — read first\n%% /refdocs %%\n",
            toRelative: "templates/macos/CLAUDE.md")

        let composer = ClaudeMdComposer(overrides: context.overrides)
        let output = try composer.compose(
            spec: NewProjectSpec(
                kind: .macOS, name: "Acme", tagline: "t",
                projectDirectory: URL(filePath: "/tmp/x")))

        #expect(output.claudeMd.contains("## Reference docs\n- PROJECT.md — read first"))
        #expect(!output.claudeMd.contains("<<<"))
    }

    @Test("Without a Base override the bundled base is used (edit is opt-in)")
    func bundledBaseWhenUnedited() throws {
        let context = try makeOverrides()
        defer { context.cleanup() }
        let composer = ClaudeMdComposer(overrides: context.overrides)

        let output = try composer.compose(
            spec: NewProjectSpec(
                kind: .other, name: "Acme", tagline: "t",
                projectDirectory: URL(filePath: "/tmp/x")))

        #expect(!output.claudeMd.contains("PLUMAGE-BASE-EDIT-"))
        #expect(!output.claudeMd.contains("<<<"))
    }
}
