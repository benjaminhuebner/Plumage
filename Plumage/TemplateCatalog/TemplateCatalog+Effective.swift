import Foundation

// The effective-content resolver: combines the three tiers into the concrete
// scaffold inputs for one template. By construction these reproduce the matching
// `ProjectKindProfile` field for every predefined kind (pinned by tests), so
// routing composition/scaffolding through here keeps output byte-identical.
nonisolated extension TemplateCatalog {
    // Shared-component layers (in component order) followed by the template's own
    // layers — e.g. macOS ⇒ ["swift-shared", "apple-shared", "macos"].
    func effectiveLayers(forTemplate templateID: String) -> [String] {
        guard let descriptor = template(id: templateID) else { return [] }
        let sharedLayers = sharedComponents(forTemplate: templateID)
            .filter { $0.kind == .layer }
            .flatMap(\.files)
        return sharedLayers + descriptor.templateLayers
    }

    // Base workflow hooks followed by member shared hooks (in component order) —
    // e.g. a Swift kind ⇒ workflow hooks + [format-swift, lint-swift, no-doc-comments].
    func effectiveHooks(forTemplate templateID: String) -> [String] {
        let sharedHooks = sharedComponents(forTemplate: templateID)
            .filter { $0.kind == .hook }
            .flatMap(\.files)
        return base.workflowHooks + sharedHooks
    }

    func effectiveGitignoreTags(forTemplate templateID: String) -> [String] {
        template(id: templateID)?.gitignoreTags ?? []
    }

    func effectiveMCPServers(forTemplate templateID: String) -> [MCPServerSpec] {
        template(id: templateID)?.mcpServers ?? []
    }

    func effectiveGateCommands(forTemplate templateID: String) -> GateCommands {
        template(id: templateID)?.gateCommands ?? .none
    }

    func effectiveStackSummary(forTemplate templateID: String) -> String {
        template(id: templateID)?.stackSummary ?? ""
    }

    func effectiveXcodeMcpLine(forTemplate templateID: String) -> String {
        template(id: templateID)?.xcodeMcpLine ?? ""
    }
}
