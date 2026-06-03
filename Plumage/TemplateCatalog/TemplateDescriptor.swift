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

    // Whether this template is offered in the New/Migrate grids. A disabled template
    // stays in the Template Manager (where it is re-enabled) but is hidden from the
    // pickers. The flag travels in the manifest overlay: a disabled predefined
    // template differs from its bundled (enabled) record and is persisted; restoring
    // it to enabled makes it equal again and drops it from the overlay.
    var enabled: Bool

    // Template-specific scaffold content (the effective resolver prepends the
    // shared-component layers/hooks to these).
    let templateLayers: [String]
    let gitignoreTags: [String]
    let mcpServers: [MCPServerSpec]
    let gateCommands: GateCommands
    let stackSummary: String
    let xcodeMcpLine: String

    init(
        id: String,
        name: String,
        image: TemplateImage,
        categoryID: String,
        predefined: Bool,
        order: Int,
        enabled: Bool = true,
        templateLayers: [String],
        gitignoreTags: [String],
        mcpServers: [MCPServerSpec],
        gateCommands: GateCommands,
        stackSummary: String,
        xcodeMcpLine: String
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.categoryID = categoryID
        self.predefined = predefined
        self.order = order
        self.enabled = enabled
        self.templateLayers = templateLayers
        self.gitignoreTags = gitignoreTags
        self.mcpServers = mcpServers
        self.gateCommands = gateCommands
        self.stackSummary = stackSummary
        self.xcodeMcpLine = xcodeMcpLine
    }

    // Forward-compat: a #00067–#00069-era manifest record has no `enabled` key and
    // decodes to enabled (the default). Other keys decode normally; `encode` stays
    // synthesized over `CodingKeys`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        image = try container.decode(TemplateImage.self, forKey: .image)
        categoryID = try container.decode(String.self, forKey: .categoryID)
        predefined = try container.decode(Bool.self, forKey: .predefined)
        order = try container.decode(Int.self, forKey: .order)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        templateLayers = try container.decode([String].self, forKey: .templateLayers)
        gitignoreTags = try container.decode([String].self, forKey: .gitignoreTags)
        mcpServers = try container.decode([MCPServerSpec].self, forKey: .mcpServers)
        gateCommands = try container.decode(GateCommands.self, forKey: .gateCommands)
        stackSummary = try container.decode(String.self, forKey: .stackSummary)
        xcodeMcpLine = try container.decode(String.self, forKey: .xcodeMcpLine)
    }
}
