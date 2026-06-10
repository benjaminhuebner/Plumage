import Foundation
import Testing

@testable import Plumage

@Suite("Scoped user-hook resolution")
struct ScopedUserHooksTests {
    private func makeOverrides() -> (overrides: ScaffoldOverrides, root: URL, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ScopedHooks-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: root),
            root, { try? FileManager.default.removeItem(at: root) }
        )
    }

    private func write(_ contents: String, to root: URL, rel: String) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("A Base hook resolves for every template; tier hooks only for their members")
    func membershipFromDirectory() throws {
        let ctx = makeOverrides()
        defer { ctx.cleanup() }
        try write("#!/bin/sh\n", to: ctx.root, rel: "hooks/base-hook.sh")
        try write("#!/bin/sh\n", to: ctx.root, rel: "components/swift-shared/hooks/comp-hook.sh")
        try write("#!/bin/sh\n", to: ctx.root, rel: "templates/macOS/hooks/tmpl-hook.sh")
        let catalog = TemplateCatalog.bundledDefault

        let macOS = catalog.effectiveUserHooks(forTemplate: "macOS", overrides: ctx.overrides)
        #expect(macOS.map(\.base) == ["base-hook", "comp-hook", "tmpl-hook"])
        #expect(
            macOS.map(\.relativePath) == [
                "hooks/base-hook.sh",
                "components/swift-shared/hooks/comp-hook.sh",
                "templates/macOS/hooks/tmpl-hook.sh",
            ])

        let iOS = catalog.effectiveUserHooks(forTemplate: "iOS", overrides: ctx.overrides)
        #expect(iOS.map(\.base) == ["base-hook", "comp-hook"])

        let other = catalog.effectiveUserHooks(forTemplate: "other", overrides: ctx.overrides)
        #expect(other.map(\.base) == ["base-hook"])
    }

    @Test("A content override of a bundled built-in is not a user hook")
    func builtInOverrideExcluded() throws {
        let ctx = makeOverrides()
        defer { ctx.cleanup() }
        try write("#!/bin/sh\n# custom\n", to: ctx.root, rel: "hooks/format-swift.sh")

        let hooks = TemplateCatalog.bundledDefault.effectiveUserHooks(
            forTemplate: "other", overrides: ctx.overrides)

        #expect(hooks.isEmpty)
    }

    @Test("A non-Bash user hook keeps its real filename")
    func realFileNamePreserved() throws {
        let ctx = makeOverrides()
        defer { ctx.cleanup() }
        try write("#!/usr/bin/env python3\n", to: ctx.root, rel: "templates/other/hooks/py-hook.py")

        let hooks = TemplateCatalog.bundledDefault.effectiveUserHooks(
            forTemplate: "other", overrides: ctx.overrides)

        #expect(hooks.map(\.base) == ["py-hook"])
        #expect(hooks.map(\.relativePath) == ["templates/other/hooks/py-hook.py"])
    }

    @Test("On a stem clash the most specific tier wins")
    func mostSpecificTierWins() throws {
        let ctx = makeOverrides()
        defer { ctx.cleanup() }
        try write("#!/bin/sh\n", to: ctx.root, rel: "hooks/dup.sh")
        try write("#!/usr/bin/env python3\n", to: ctx.root, rel: "templates/macOS/hooks/dup.py")

        let macOS = TemplateCatalog.bundledDefault.effectiveUserHooks(
            forTemplate: "macOS", overrides: ctx.overrides)
        #expect(macOS.map(\.relativePath) == ["templates/macOS/hooks/dup.py"])

        let other = TemplateCatalog.bundledDefault.effectiveUserHooks(
            forTemplate: "other", overrides: ctx.overrides)
        #expect(other.map(\.relativePath) == ["hooks/dup.sh"])
    }

    @Test("No override store resolves to no user hooks")
    func noStoreNoHooks() {
        let overrides = ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: nil)
        let hooks = TemplateCatalog.bundledDefault.effectiveUserHooks(
            forTemplate: "macOS", overrides: overrides)
        #expect(hooks.isEmpty)
    }
}
