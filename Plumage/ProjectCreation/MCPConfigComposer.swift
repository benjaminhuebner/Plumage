import Foundation

// Single source of truth for generated `.mcp.json`: scaffolder, migrator and the
// manager preview compose through here so they can't drift (they were three copies).
nonisolated struct MCPConfigComposer {
    var catalog: TemplateCatalog = .bundledDefault

    // Typed envelope instead of [String: Any] + JSONSerialization: the
    // compiler now checks the shape, and a future field can't silently
    // produce mixed-type dictionaries.
    private struct Envelope: Encodable {
        let mcpServers: [String: ServerEntry]
    }

    private struct ServerEntry: Encodable {
        let command: String
        let args: [String]?
        let env: [String: String]?
    }

    func mcpJSON(forTemplate templateID: String) throws -> Data {
        var servers: [String: ServerEntry] = [:]
        for server in catalog.effectiveMCPServers(forTemplate: templateID) {
            servers[server.name] = ServerEntry(
                command: server.command,
                args: server.args.isEmpty ? nil : server.args,
                env: server.env.isEmpty ? nil : server.env
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(mcpServers: servers))
    }
}
