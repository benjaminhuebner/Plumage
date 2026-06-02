import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplatesSettingsModel")
struct TemplatesSettingsModelTests {
    private struct Harness {
        let model: TemplatesSettingsModel
        let override: URL
        let wiringURL: URL
        let cleanup: () -> Void
    }

    // A model rooted at the real bundled assets with an isolated, empty override
    // store and hook-wiring file under a temp dir, so behavior is hermetic.
    private func makeModel() -> Harness {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TemplatesModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        let overrideRoot = base.appending(path: "NewProjectAssets", directoryHint: .isDirectory)
        let wiringURL = base.appending(path: "hook-wirings.json")
        let overrides = ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: overrideRoot)
        return Harness(
            model: TemplatesSettingsModel(overrides: overrides, hookWiringStoreURL: wiringURL),
            override: overrideRoot, wiringURL: wiringURL,
            cleanup: { try? fm.removeItem(at: base) })
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

    @Test("addTemplate creates a skill SKILL.md starter and selects it")
    func addSkill() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(ctx.model.addTemplate(category: .skills, name: "my-skill"))
        #expect(ctx.model.selection == "skills/my-skill/SKILL.md")
        let entry = ctx.model.entries.first { $0.relativePath == "skills/my-skill/SKILL.md" }
        #expect(entry?.userAuthored == true)
        #expect(entry?.category == .skills)
        let md = try String(
            contentsOf: ctx.override.appending(path: "skills/my-skill/SKILL.md"), encoding: .utf8)
        #expect(md.contains("name: my-skill"))
    }

    @Test("An override-only skill joins the catalog; bundled skills stay non-user-authored")
    func overrideOnlySkillUnion() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let md = ctx.override.appending(path: "skills/custom/SKILL.md")
        try FileManager.default.createDirectory(
            at: md.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: custom\n---\n".write(to: md, atomically: true, encoding: .utf8)

        ctx.model.reload()
        let entry = ctx.model.entries.first { $0.relativePath == "skills/custom/SKILL.md" }
        #expect(entry?.userAuthored == true)
        let bundled = ctx.model.entries.first { $0.relativePath == "skills/plumage-plan/SKILL.md" }
        #expect(bundled?.userAuthored == false)
    }

    @Test("Deleting a user skill removes the whole skill directory")
    func deleteSkillDir() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(ctx.model.addTemplate(category: .skills, name: "scratch-skill"))
        let entry = try #require(
            ctx.model.entries.first { $0.relativePath == "skills/scratch-skill/SKILL.md" })
        ctx.model.delete(entry)
        #expect(
            !FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "skills/scratch-skill").path))
        #expect(!ctx.model.entries.contains { $0.relativePath == "skills/scratch-skill/SKILL.md" })
    }

    @Test("Editor dirty state tracks setEditorDirty and resets on beginEditing")
    func editorDirtyLifecycle() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(!ctx.model.isEditorDirty)
        ctx.model.setEditorDirty(true)
        #expect(ctx.model.isEditorDirty)
        // Opening another entry clears the dirty flag (no stale Reset on the next row).
        let entry = try #require(ctx.model.entries.first { $0.relativePath == "docs/PROJECT.md" })
        ctx.model.beginEditing(entry)
        #expect(!ctx.model.isEditorDirty)
    }

    @Test("An override-only hook joins the catalog as user-authored")
    func overrideOnlyHookUnion() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let url = ctx.override.appending(path: "hooks/my-hook.sh")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)

        ctx.model.reload()
        let entry = ctx.model.entries.first { $0.relativePath == "hooks/my-hook.sh" }
        #expect(entry?.userAuthored == true)
        // A bundled hook stays non-user-authored.
        let bundled = ctx.model.entries.first { $0.relativePath == "hooks/force-plumage-skill.sh" }
        #expect(bundled?.userAuthored == false)
    }

    @Test("addTemplate(.hooks) writes the .sh and persists its wiring")
    func addHookPersistsWiring() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(
            ctx.model.addTemplate(
                category: .hooks, name: "my-hook", wiring: (event: .preToolUse, matcher: "Edit|Write")))
        #expect(ctx.model.selection == "hooks/my-hook.sh")
        #expect(
            FileManager.default.fileExists(atPath: ctx.override.appending(path: "hooks/my-hook.sh").path))

        let store = try HookWiringStore.load(from: ctx.wiringURL)
        let wiring = try #require(store.wiring(named: "my-hook"))
        #expect(wiring.event == .preToolUse)
        #expect(wiring.matcher == "Edit|Write")
    }

    @Test("Deleting a user hook removes its file and its wiring")
    func deleteHookDropsWiring() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        #expect(ctx.model.addTemplate(category: .hooks, name: "my-hook", wiring: (event: .stop, matcher: nil)))
        let entry = try #require(ctx.model.entries.first { $0.relativePath == "hooks/my-hook.sh" })
        ctx.model.delete(entry)

        #expect(!FileManager.default.fileExists(atPath: ctx.override.appending(path: "hooks/my-hook.sh").path))
        let store = try HookWiringStore.load(from: ctx.wiringURL)
        #expect(store.wiring(named: "my-hook") == nil)
    }
}
