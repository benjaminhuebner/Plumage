import Foundation
import Testing

@testable import Plumage

// The hard safety net for Phase B: routing composition/scaffold through the
// shared-component catalog must produce byte-identical artifacts to driving them
// straight from `ProjectKind.profile`. We build an independent "flat" catalog
// directly from each profile (one descriptor, no shared components, all hooks in
// the base) and assert the rich bundled catalog yields the same bytes per kind.
@Suite("Catalog-driven output == profile-driven output (byte-identical)")
struct CatalogByteIdentityTests {
    private let overrides = ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: nil)

    // A catalog that reproduces a single kind's profile without the shared-component
    // decomposition — the reference representation.
    private func flatProfileCatalog(for kind: ProjectKind) -> TemplateCatalog {
        let profile = kind.profile
        return TemplateCatalog(
            base: BaseTemplate(
                id: "base", name: "Base", claudeMdRelativePath: "templates/CLAUDE.md",
                workflowHooks: profile.hookNames),
            categories: [TemplateCategory(id: kind.group.rawValue, name: kind.group.displayName, order: 0)],
            sharedComponents: [],
            templates: [
                TemplateDescriptor(
                    id: kind.rawValue, name: kind.displayName, image: .symbol("doc"),
                    categoryID: kind.group.rawValue, predefined: true, order: 0,
                    templateLayers: profile.templateLayers,
                    gitignoreTags: profile.gitignoreTags,
                    mcpServers: profile.mcpServers,
                    gateCommands: profile.gateCommands,
                    stackSummary: profile.stackSummary,
                    xcodeMcpLine: profile.xcodeMcpLine)
            ]
        )
    }

    private func spec(_ kind: ProjectKind) -> NewProjectSpec {
        NewProjectSpec(
            kind: kind, name: "Acme", tagline: "A tiny thing",
            projectDirectory: URL(filePath: "/tmp/acme"))
    }

    @Test("Composed CLAUDE.md is identical", arguments: ProjectKind.allCases)
    func claudeMdIdentical(_ kind: ProjectKind) throws {
        let viaBundled = try ClaudeMdComposer(overrides: overrides, catalog: .bundledDefault)
            .compose(spec: spec(kind))
        let viaProfile = try ClaudeMdComposer(overrides: overrides, catalog: flatProfileCatalog(for: kind))
            .compose(spec: spec(kind))
        #expect(viaBundled.claudeMd == viaProfile.claudeMd)
    }

    @Test("Composed .gitignore is identical", arguments: ProjectKind.allCases)
    func gitignoreIdentical(_ kind: ProjectKind) throws {
        let viaBundled = try GitignoreComposer(overrides: overrides, catalog: .bundledDefault)
            .compose(for: kind)
        let viaProfile = try GitignoreComposer(overrides: overrides, catalog: flatProfileCatalog(for: kind))
            .compose(for: kind)
        #expect(viaBundled == viaProfile)
    }

    @Test("Composed settings.json is identical", arguments: ProjectKind.allCases)
    func settingsIdentical(_ kind: ProjectKind) throws {
        let viaBundled = try SettingsComposer(catalog: .bundledDefault).settingsJSON(for: kind)
        let viaProfile = try SettingsComposer(catalog: flatProfileCatalog(for: kind)).settingsJSON(for: kind)
        #expect(viaBundled == viaProfile)
    }
}
