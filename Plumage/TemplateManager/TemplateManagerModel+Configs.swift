import Foundation

// The generated config files surfaced in the manager. They are not stored assets:
// the composers produce their content from catalog fields, so the manager shows that
// generated text as a read-only baseline and lets the user override it through the
// global override slot (a saved override wins at scaffold — B2). Each config's
// relative path is its output path, so it places itself correctly in the tree.
extension TemplateManagerModel {
    enum ManagerConfig: String, CaseIterable, Sendable {
        case gitignore = ".gitignore"
        case mcp = ".mcp.json"
        case settings = ".claude/settings.json"

        var relativePath: String { rawValue }
        var displayName: String { (rawValue as NSString).lastPathComponent }
    }

    func managerConfig(forRelative relativePath: String) -> ManagerConfig? {
        ManagerConfig(rawValue: relativePath)
    }

    // The generated content is a global, template-neutral baseline (the override it
    // seeds is global and wins for every template at scaffold), so it is rendered for
    // a representative template rather than any one selection.
    private var representativeConfigTemplateID: String {
        let other = ProjectKind.other.rawValue
        if catalog.template(id: other) != nil { return other }
        return catalog.templates.first?.id ?? other
    }

    func generatedConfigContent(_ config: ManagerConfig) -> String {
        let templateID = representativeConfigTemplateID
        switch config {
        case .gitignore:
            return
                (try? GitignoreComposer(overrides: overrides, catalog: catalog)
                .compose(forTemplate: templateID)) ?? ""
        case .mcp:
            return generatedMCPJSON(forTemplate: templateID)
        case .settings:
            let data = try? SettingsComposer(catalog: catalog).settingsJSON(
                forTemplate: templateID, toggles: ScaffoldToggles(), userWirings: hookWirings.wirings)
            return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
    }

    // Mirrors `ProjectScaffolder.writeMCPConfig` so the preview matches the scaffolded
    // file byte-for-byte.
    private func generatedMCPJSON(forTemplate templateID: String) -> String {
        var servers: [String: Any] = [:]
        for server in catalog.effectiveMCPServers(forTemplate: templateID) {
            var entry: [String: Any] = ["command": server.command]
            if !server.args.isEmpty { entry["args"] = server.args }
            if !server.env.isEmpty { entry["env"] = server.env }
            servers[server.name] = entry
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["mcpServers": servers],
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // A config always shows in the tree (even with no override yet); its node points
    // at the override slot so editing materializes a global override there.
    func configNode(_ config: ManagerConfig) -> FileNode {
        let url =
            overrides.overrideURL(forRelative: config.relativePath)
            ?? overrides.bundledRoot.appending(path: config.relativePath)
        return FileNode(
            url: url, relativePath: config.relativePath, name: config.displayName,
            isDirectory: false, children: nil)
    }
}
