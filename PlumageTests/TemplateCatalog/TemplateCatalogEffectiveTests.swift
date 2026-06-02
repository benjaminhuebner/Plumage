import Foundation
import Testing

@testable import Plumage

// The data-level byte-identity safety net: the effective resolver must reproduce
// every predefined kind's ProjectKindProfile exactly. If this drifts, composed
// CLAUDE.md / scaffold output drifts with it.
@Suite("TemplateCatalog effective resolver == ProjectKindProfile")
struct TemplateCatalogEffectiveTests {
    private let catalog = TemplateCatalog.bundledDefault

    @Test("Effective layers reproduce profile.templateLayers (order included)", arguments: ProjectKind.allCases)
    func effectiveLayers(_ kind: ProjectKind) {
        #expect(catalog.effectiveLayers(forTemplate: kind.rawValue) == kind.profile.templateLayers)
    }

    @Test("Effective hooks reproduce profile.hookNames (order included)", arguments: ProjectKind.allCases)
    func effectiveHooks(_ kind: ProjectKind) {
        #expect(catalog.effectiveHooks(forTemplate: kind.rawValue) == kind.profile.hookNames)
    }

    @Test("Effective gitignore tags reproduce the profile", arguments: ProjectKind.allCases)
    func effectiveGitignore(_ kind: ProjectKind) {
        #expect(catalog.effectiveGitignoreTags(forTemplate: kind.rawValue) == kind.profile.gitignoreTags)
    }

    @Test("Effective MCP servers reproduce the profile", arguments: ProjectKind.allCases)
    func effectiveMCP(_ kind: ProjectKind) {
        #expect(catalog.effectiveMCPServers(forTemplate: kind.rawValue) == kind.profile.mcpServers)
    }

    @Test("Effective gate / stack / xcode-mcp line reproduce the profile", arguments: ProjectKind.allCases)
    func effectiveScalars(_ kind: ProjectKind) {
        #expect(catalog.effectiveGateCommands(forTemplate: kind.rawValue) == kind.profile.gateCommands)
        #expect(catalog.effectiveStackSummary(forTemplate: kind.rawValue) == kind.profile.stackSummary)
        #expect(catalog.effectiveXcodeMcpLine(forTemplate: kind.rawValue) == kind.profile.xcodeMcpLine)
    }

    @Test("Unknown template id resolves to empty/none, never crashes")
    func unknownTemplate() {
        #expect(catalog.effectiveLayers(forTemplate: "nope").isEmpty)
        #expect(catalog.effectiveHooks(forTemplate: "nope") == catalog.base.workflowHooks)
        #expect(catalog.effectiveGateCommands(forTemplate: "nope") == .none)
    }
}
