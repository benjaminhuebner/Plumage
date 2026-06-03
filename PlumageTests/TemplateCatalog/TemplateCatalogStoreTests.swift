import Foundation
import Testing

@testable import Plumage

@Suite("TemplateCatalogStore + bundled default")
struct TemplateCatalogStoreTests {
    // MARK: - Store resolution

    @Test("No manifest ⇒ bundled default")
    func missingManifestFallsBackToBundled() {
        let store = TemplateCatalogStore(manifestURL: nil)
        #expect(store.load() == .bundledDefault)
    }

    @Test("Manifest pointing at a nonexistent file ⇒ bundled default")
    func nonexistentManifestFile() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "does-not-exist-\(UUID().uuidString).json")
        #expect(TemplateCatalogStore(manifestURL: url).load() == .bundledDefault)
    }

    @Test("Unreadable/garbage manifest ⇒ bundled default (no crash)")
    func garbageManifestFallsBack() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "garbage-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(TemplateCatalogStore(manifestURL: url).load() == .bundledDefault)
    }

    @Test("A valid manifest on disk is loaded and overrides the bundled default")
    func validManifestIsLoaded() throws {
        let custom = TemplateCatalog(
            base: BaseTemplate(
                id: "base", name: "Base", claudeMdRelativePath: "templates/CLAUDE.md",
                workflowHooks: ["force-plumage-skill"]),
            categories: [TemplateCategory(id: "custom", name: "Custom", order: 0)],
            sharedComponents: [],
            templates: []
        ).manifest
        let url = FileManager.default.temporaryDirectory
            .appending(path: "manifest-\(UUID().uuidString).json")
        try JSONEncoder().encode(custom).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = TemplateCatalogStore(manifestURL: url).load()
        #expect(loaded == TemplateCatalog(manifest: custom))
        #expect(loaded != .bundledDefault)
    }

    // MARK: - Bundled default mirrors today's ProjectKind set

    @Test("Categories equal the ProjectKindGroup set, in declaration order")
    func categoriesMatchGroups() {
        let catalog = TemplateCatalog.bundledDefault
        let expected = ProjectKindGroup.allCases.map(\.rawValue)
        #expect(catalog.sortedCategories.map(\.id) == expected)
        #expect(
            catalog.category(id: ProjectKindGroup.appleApps.rawValue)?.name == "Apple Apps")
        #expect(
            catalog.category(id: ProjectKindGroup.serverside.rawValue)?.name == "Serverside Swift")
    }

    @Test("Templates equal the ProjectKind set, one per kind, in the right category")
    func templatesMatchKinds() {
        let catalog = TemplateCatalog.bundledDefault
        #expect(catalog.templates.count == ProjectKind.allCases.count)
        for kind in ProjectKind.allCases {
            let descriptor = catalog.template(id: kind.rawValue)
            #expect(descriptor != nil)
            #expect(descriptor?.name == kind.displayName)
            #expect(descriptor?.categoryID == kind.group.rawValue)
            #expect(descriptor?.predefined == true)
        }
    }

    // MARK: - Shared-component memberships reproduce today's behavior

    @Test("swift-shared ∈ all Swift kinds (all except .other)")
    func swiftSharedMembership() throws {
        let catalog = TemplateCatalog.bundledDefault
        let swiftShared = try #require(catalog.sharedComponent(id: "swift-shared"))
        let expected = Set(ProjectKind.allCases.filter(\.isSwift).map(\.rawValue))
        #expect(swiftShared.memberTemplateIDs == expected)
        #expect(!swiftShared.isMember(ProjectKind.other.rawValue))
        // Swift Shared now carries both the layer fragment and the tooling hooks.
        #expect(swiftShared.files(ofKind: .layer) == ["swift-shared"])
        #expect(swiftShared.files(ofKind: .hook) == ["format-swift", "lint-swift", "no-doc-comments"])
    }

    @Test("apple-shared ∈ exactly the three Apple kinds")
    func appleSharedMembership() throws {
        let catalog = TemplateCatalog.bundledDefault
        let appleShared = try #require(catalog.sharedComponent(id: "apple-shared"))
        let expected = Set(
            [ProjectKind.appleMultiplatform, .macOS, .iOS].map(\.rawValue))
        #expect(appleShared.memberTemplateIDs == expected)
        #expect(!appleShared.isMember(ProjectKind.vapor.rawValue))
    }

    @Test("Swift tooling hooks are folded into swift-shared (no separate component)")
    func swiftToolingHooksFolded() throws {
        let catalog = TemplateCatalog.bundledDefault
        #expect(catalog.sharedComponent(id: "swift-tooling-hooks") == nil)
        let swiftShared = try #require(catalog.sharedComponent(id: "swift-shared"))
        #expect(swiftShared.files(ofKind: .hook) == ["format-swift", "lint-swift", "no-doc-comments"])
    }

    @Test("Bundled base carries the workflow hooks")
    func baseWorkflowHooks() {
        #expect(TemplateCatalog.bundledDefault.base.workflowHooks == ProjectKindProfile.workflowHooks)
    }
}
