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

    // The override this baseline seeds is global, so it must be template-neutral.
    // `ProjectKind.other` is the minimal profile, and the `effective*` resolvers fall
    // back to base-only values for it even if its descriptor was deleted — so use the id
    // directly rather than risk an arbitrary (possibly flavored) catalog template.
    private var neutralBaselineTemplateID: String { ProjectKind.other.rawValue }

    func generatedConfigContent(_ config: ManagerConfig) -> String {
        let templateID = neutralBaselineTemplateID
        switch config {
        case .gitignore:
            return
                (try? GitignoreComposer(overrides: overrides, catalog: catalog)
                .compose(forTemplate: templateID)) ?? ""
        case .mcp:
            let data = try? MCPConfigComposer(catalog: catalog).mcpJSON(forTemplate: templateID)
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        case .settings:
            let data = try? SettingsComposer(catalog: catalog).settingsJSON(
                forTemplate: templateID, toggles: ScaffoldToggles(), userWirings: hookWirings.wirings)
            return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
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
