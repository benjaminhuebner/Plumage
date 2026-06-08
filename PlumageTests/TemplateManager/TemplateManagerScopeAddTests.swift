import Foundation
import Testing

@testable import Plumage

// Authoring writes into the active tier's scope root, and only a hook still joins a
// component's manifest membership (#00078).
@MainActor
@Suite("TemplateManager scope-rooted authoring (#00078)")
struct TemplateManagerScopeAddTests {
    private func makeModel() -> (model: TemplateManagerModel, override: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMScopeAdd-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = base.appending(path: "bundled", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try? fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try? fm.createDirectory(at: override, withIntermediateDirectories: true)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: base.appending(path: "manifest.json")),
            overrides: ScaffoldOverrides(bundledRoot: bundled, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json"))
        return (model, override, { try? fm.removeItem(at: base) })
    }

    @Test("A doc authored under a template lands in that template's scope")
    func addDocInTemplateScope() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()

        let node = try #require(ctx.model.addUserFile(kind: .doc, rawName: "notes"))
        #expect(node.relativePath == "templates/macOS/docs/notes.md")
        #expect(ctx.model.overrides.hasOverride(forRelative: "templates/macOS/docs/notes.md"))
        // It belongs to that template only — no sibling template owns it.
        #expect(!ctx.model.overrides.hasOverride(forRelative: "templates/iOS/docs/notes.md"))
        #expect(!ctx.model.overrides.hasOverride(forRelative: "docs/notes.md"))
    }

    @Test("A doc authored under a component lands in its subtree, with no manifest membership")
    func addDocInComponentScopeNoMembership() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()
        let filesBefore = ctx.model.catalog.sharedComponent(id: "swift-shared")?.files

        let node = try #require(ctx.model.addUserFile(kind: .doc, rawName: "notes"))
        #expect(node.relativePath == "components/swift-shared/docs/notes.md")
        #expect(ctx.model.catalog.sharedComponent(id: "swift-shared")?.files == filesBefore)
    }

    @Test("A skill authored under a component is a scope-owned folder, not a .skill membership")
    func addSkillInComponentScopeNoMembership() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        let node = try #require(ctx.model.addUserFile(kind: .skill, rawName: "my-skill"))
        #expect(node.relativePath == "components/swift-shared/skills/my-skill/SKILL.md")
        #expect(
            ctx.model.overrides.hasOverride(
                forRelative: "components/swift-shared/skills/my-skill/SKILL.md"))
        #expect(ctx.model.catalog.sharedComponent(id: "swift-shared")?.files(ofKind: .skill).isEmpty == true)
    }

    @Test("Deleting a component skill via its SKILL.md leaf trashes the whole skill folder")
    func deleteComponentSkillTrashesWholeFolder() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()
        let leaf = try #require(ctx.model.addUserFile(kind: .skill, rawName: "my-skill"))
        try "ref".write(
            to: ctx.override.appending(
                path: "components/swift-shared/skills/my-skill/reference.md"),
            atomically: true, encoding: .utf8)
        ctx.model.refreshContent()

        // `leaf` is the SKILL.md leaf (what `selectCreatedFile` selects).
        #expect(leaf.relativePath == "components/swift-shared/skills/my-skill/SKILL.md")
        ctx.model.requestDelete(leaf)
        if ctx.model.pendingDeleteConfirmation != nil { ctx.model.confirmPendingDelete() }

        let fm = FileManager.default
        #expect(
            !fm.fileExists(
                atPath: ctx.override.appending(path: "components/swift-shared/skills/my-skill").path))
    }

    @Test("Renaming a component skill via its SKILL.md leaf renames the skill folder")
    func renameComponentSkillRenamesFolder() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()
        let leaf = try #require(ctx.model.addUserFile(kind: .skill, rawName: "my-skill"))

        ctx.model.beginRenameContent(leaf)
        // The rename session escalates to the skill folder, not SKILL.md.
        #expect(ctx.model.contentRename?.isDirectory == true)
        #expect(ctx.model.contentRename?.storePath == "components/swift-shared/skills/my-skill")
        ctx.model.contentRename?.name = "renamed"
        ctx.model.commitContentRename()

        let fm = FileManager.default
        #expect(
            fm.fileExists(
                atPath: ctx.override.appending(
                    path: "components/swift-shared/skills/renamed/SKILL.md"
                ).path))
        #expect(
            !fm.fileExists(
                atPath: ctx.override.appending(path: "components/swift-shared/skills/my-skill").path))
    }

    @Test("A hook authored under a component stays global and still joins membership")
    func addHookInComponentStillGlobalAndJoins() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        let node = try #require(ctx.model.addUserFile(kind: .hook, rawName: "my-hook"))
        #expect(node.relativePath == "hooks/my-hook.sh")  // global composition asset
        #expect(ctx.model.overrides.hasOverride(forRelative: "hooks/my-hook.sh"))
        #expect(
            ctx.model.catalog.sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("my-hook") == true)
    }

    @Test("A .py hook under a component is a base-name member resolved to its real filename")
    func addPythonHookInComponentResolvesFilename() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        let node = try #require(ctx.model.addUserFile(kind: .hook, rawName: "py-hook.py"))
        #expect(node.relativePath == "hooks/py-hook.py")  // real extension on disk
        #expect(ctx.model.overrides.hasOverride(forRelative: "hooks/py-hook.py"))
        // The membership key stays the base name; the real filename is resolved from it.
        #expect(
            ctx.model.catalog.sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("py-hook") == true)
        #expect(ctx.model.relativePath(for: .hook, file: "py-hook") == "hooks/py-hook.py")
    }

    @Test("A typeless folder authored under a template lands in the template's scope")
    func addFolderInTemplateScope() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()
        ctx.model.selectedFile = nil  // add at the scope root

        let node = try #require(ctx.model.addUserFile(kind: .folder, rawName: "drafts"))
        #expect(node.isDirectory)
        #expect(node.relativePath == "drafts")  // output position at the project root
        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "templates/macOS/drafts").path))
    }

    @Test("With a folder selected, every kind is created inside it")
    func addInsideSelectedFolder() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()
        ctx.model.selectedFile = nil
        _ = ctx.model.addUserFile(kind: .folder, rawName: "box")
        #expect(TemplateManagerModel.findNode(in: ctx.model.contentTree, relativePath: "box") != nil)

        func selectBox() {
            ctx.model.selectedFile = TemplateManagerModel.findNode(
                in: ctx.model.contentTree, relativePath: "box")
        }

        selectBox()
        let doc = try #require(ctx.model.addUserFile(kind: .doc, rawName: "inside"))
        #expect(doc.relativePath == "templates/macOS/box/inside.md")

        selectBox()
        let skill = try #require(ctx.model.addUserFile(kind: .skill, rawName: "myskill"))
        #expect(skill.relativePath == "templates/macOS/box/myskill/SKILL.md")

        selectBox()
        let file = try #require(ctx.model.addUserFile(kind: .file, rawName: "raw.txt"))
        #expect(file.relativePath == "templates/macOS/box/raw.txt")
    }

    @Test("With nothing/a file selected, typed kinds still default to their canonical dir")
    func typedKindsDefaultToCanonical() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()  // auto-selects a config file, not a folder
        let doc = try #require(ctx.model.addUserFile(kind: .doc, rawName: "notes"))
        #expect(doc.relativePath == "templates/macOS/docs/notes.md")
    }

    @Test("A typeless add clamps to scope when an out-of-scope file (the layer) is selected")
    func typelessAddClampsToComponentScope() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        // The component's layer CLAUDE.md lives under templates/<layer> — outside the
        // component's components/<id> subtree. Selecting it (as refreshContent does by
        // default) must not pull a new loose folder out into the shared layer namespace.
        ctx.model.selectedFile = FileNode(
            url: ctx.override, relativePath: "templates/swift-shared/CLAUDE.md",
            name: "CLAUDE.md", isDirectory: false, children: nil)
        #expect(ctx.model.addTargetStorageDir() == "components/swift-shared")

        let node = try #require(ctx.model.addUserFile(kind: .folder, rawName: "drafts"))
        #expect(node.relativePath == "drafts")
        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "components/swift-shared/drafts").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "templates/swift-shared/drafts").path))
    }

    @Test("A typeless add still targets a selected folder inside the active scope")
    func typelessAddRespectsInScopeFolder() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.selectedFile = FileNode(
            url: ctx.override, relativePath: ".claude/docs", name: "docs",
            isDirectory: true, children: nil)
        #expect(ctx.model.addTargetStorageDir() == "templates/macOS/docs")
    }

    @Test("Dropping a skill onto a component stores it in the component's scope, no membership")
    func dropSkillOntoComponentIsScoped() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let fm = FileManager.default
        let src = fm.temporaryDirectory.appending(
            path: "DropSkill-\(UUID().uuidString)", directoryHint: .isDirectory)
        let skill = src.appending(path: "myskill", directoryHint: .isDirectory)
        try fm.createDirectory(at: skill, withIntermediateDirectories: true)
        try "x\n".write(to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: src) }

        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()
        _ = ctx.model.importDropped(urls: [skill])

        #expect(
            ctx.model.overrides.hasOverride(
                forRelative: "components/swift-shared/skills/myskill/SKILL.md"))
        #expect(!ctx.model.overrides.hasOverride(forRelative: "skills/myskill/SKILL.md"))
        #expect(ctx.model.catalog.sharedComponent(id: "swift-shared")?.files(ofKind: .skill).isEmpty == true)
    }
}
