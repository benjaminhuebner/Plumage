import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplatesSettingsModel")
struct TemplatesSettingsModelTests {
    private struct Harness {
        let model: TemplatesSettingsModel
        let override: URL
        let cleanup: () -> Void
    }

    // A model rooted at the real bundled assets with an isolated, empty override
    // store under a temp dir, so catalog/add/delete behavior is hermetic.
    private func makeModel() -> Harness {
        let fm = FileManager.default
        let overrideRoot = fm.temporaryDirectory.appending(
            path: "TemplatesModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        let overrides = ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: overrideRoot)
        return Harness(
            model: TemplatesSettingsModel(overrides: overrides), override: overrideRoot,
            cleanup: { try? fm.removeItem(at: overrideRoot) })
    }

    @Test("Bundled docs are catalogued and not user-authored")
    func bundledDocsCatalogued() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let docs = ctx.model.entries.filter { $0.category == .docs }
        #expect(docs.contains { $0.relativePath == "docs/PROJECT.md" })
        #expect(docs.allSatisfy { !$0.userAuthored })
    }

    @Test("An override-only doc joins the catalog as user-authored")
    func overrideOnlyDocUnion() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let url = ctx.override.appending(path: "docs/guide.md")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Guide\n".write(to: url, atomically: true, encoding: .utf8)

        ctx.model.reload()
        let entry = ctx.model.entries.first { $0.relativePath == "docs/guide.md" }
        #expect(entry?.userAuthored == true)
        #expect(entry?.category == .docs)
    }

    @Test("addTemplate writes a doc starter and selects it")
    func addDocSelects() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(ctx.model.addTemplate(category: .docs, name: "onboarding"))
        #expect(ctx.model.selection == "docs/onboarding.md")
        let entry = ctx.model.entries.first { $0.relativePath == "docs/onboarding.md" }
        #expect(entry?.userAuthored == true)
        #expect(
            FileManager.default.fileExists(atPath: ctx.override.appending(path: "docs/onboarding.md").path))
    }

    @Test("addTemplate writes a plumage script with a shebang by extension")
    func addScriptShebang() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(ctx.model.addTemplate(category: .plumageScripts, name: "deploy.py"))
        let py = try String(contentsOf: ctx.override.appending(path: "plumage/deploy.py"), encoding: .utf8)
        #expect(py.hasPrefix("#!/usr/bin/env python3"))

        #expect(ctx.model.addTemplate(category: .plumageScripts, name: "build"))
        let sh = try String(contentsOf: ctx.override.appending(path: "plumage/build"), encoding: .utf8)
        #expect(sh.hasPrefix("#!/bin/sh"))
    }

    @Test("addTemplate on a bundled name selects the existing entry, no duplicate")
    func addCollisionSelectsExisting() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let before = ctx.model.entries.count
        #expect(ctx.model.addTemplate(category: .docs, name: "PROJECT"))
        #expect(ctx.model.selection == "docs/PROJECT.md")
        #expect(ctx.model.entries.count == before)
        // A bundled-name "add" must not seed an override file.
        #expect(
            !FileManager.default.fileExists(atPath: ctx.override.appending(path: "docs/PROJECT.md").path))
    }

    @Test("A name that sanitises to empty is a no-op")
    func invalidNameNoOp() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(!ctx.model.addTemplate(category: .docs, name: "   "))
        #expect(!ctx.model.addTemplate(category: .docs, name: ""))
    }

    @Test("delete removes a user-authored item and clears its selection")
    func deleteUserItem() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(ctx.model.addTemplate(category: .docs, name: "scratch"))
        let entry = try #require(ctx.model.entries.first { $0.relativePath == "docs/scratch.md" })
        ctx.model.delete(entry)
        #expect(!ctx.model.entries.contains { $0.relativePath == "docs/scratch.md" })
        #expect(ctx.model.selection == nil)
        #expect(
            !FileManager.default.fileExists(atPath: ctx.override.appending(path: "docs/scratch.md").path))
    }

    @Test("delete is a no-op for a bundled entry")
    func deleteBundledNoOp() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let bundled = try #require(ctx.model.entries.first { $0.relativePath == "docs/PROJECT.md" })
        ctx.model.delete(bundled)
        #expect(ctx.model.entries.contains { $0.relativePath == "docs/PROJECT.md" })
    }
}
