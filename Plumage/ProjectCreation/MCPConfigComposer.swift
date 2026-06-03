import Foundation

// Single source of truth for generated `.mcp.json`: scaffolder, migrator and the
// manager preview compose through here so they can't drift (they were three copies).
nonisolated struct MCPConfigComposer {
    var catalog: TemplateCatalog = .bundledDefault

    func mcpJSON(forTemplate templateID: String) throws -> Data {
        var servers: [String: Any] = [:]
        for server in catalog.effectiveMCPServers(forTemplate: templateID) {
            var entry: [String: Any] = ["command": server.command]
            if !server.args.isEmpty { entry["args"] = server.args }
            if !server.env.isEmpty { entry["env"] = server.env }
            servers[server.name] = entry
        }
        return try JSONSerialization.data(
            withJSONObject: ["mcpServers": servers],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
