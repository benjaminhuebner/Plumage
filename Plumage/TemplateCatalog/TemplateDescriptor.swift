import Foundation

// The third tier: a concrete template. Owns its template-specific content (its
// own `CLAUDE.md` layer(s) and per-kind scaffold settings) plus metadata. The
// shared components it belongs to are expressed on `SharedComponent.memberTemplateIDs`,
// not here — keeping membership single-sourced.
nonisolated struct TemplateDescriptor: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var name: String
    var image: TemplateImage
    var categoryID: String
    let predefined: Bool
    var order: Int

    // Template-specific scaffold content (the effective resolver prepends the
    // shared-component layers/hooks to these).
    let templateLayers: [String]
    let gitignoreTags: [String]
    let mcpServers: [MCPServerSpec]
    let gateCommands: GateCommands
    let stackSummary: String
    let xcodeMcpLine: String
}
