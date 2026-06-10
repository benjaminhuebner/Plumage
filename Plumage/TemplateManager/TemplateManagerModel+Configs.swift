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
            let data = try? SettingsComposer(catalog: catalog, overrides: overrides).settingsJSON(
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

    // MARK: - Per-tier generated settings preview

    // A synthetic, non-store path so the read-only preview never collides with a real
    // override slot (a tier's `.claude/settings.json` is a legitimate loose file).
    static func tierSettingsPreviewPath(for scope: ManagerScope) -> String? {
        switch scope {
        case .base: return nil
        case .template, .component: return "\(scope.storageRoot)/generated-settings-preview"
        }
    }

    static func isTierSettingsPreviewPath(_ path: String) -> Bool {
        path.hasSuffix("/generated-settings-preview")
            && (path.hasPrefix("templates/") || path.hasPrefix("components/"))
    }

    func tierSettingsPreviewNode(for scope: ManagerScope) -> FileNode? {
        guard let path = Self.tierSettingsPreviewPath(for: scope) else { return nil }
        return FileNode(
            url: overrides.bundledRoot.appending(path: path), relativePath: path,
            name: "settings.json", isDirectory: false, children: nil)
    }

    // Exactly what this tier contributes to a scaffolded settings.json: a component's
    // built-in manifest hooks plus its scoped user hooks; a template's scoped user hooks.
    func tierSettingsPreviewContent(for scope: ManagerScope) -> String {
        var builtinNames: [String] = []
        if case .component(let id) = scope, let component = catalog.sharedComponent(id: id) {
            builtinNames = component.files(ofKind: .hook)
        }
        let bases = Set(
            overrides.overrideFileNames(inRelativeDir: "\(scope.storageRoot)/hooks")
                .map { ($0 as NSString).deletingPathExtension })
        let userWirings = hookWirings.wirings.filter { bases.contains($0.name) }
        let data = try? SettingsComposer(catalog: catalog, overrides: overrides)
            .tierHooksJSON(builtinNames: builtinNames, userWirings: userWirings)
        return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
