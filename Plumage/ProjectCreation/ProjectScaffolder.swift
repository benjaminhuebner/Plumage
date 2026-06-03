import Foundation

nonisolated struct CreatedProject: Hashable, Sendable {
    let root: URL
    let bundle: URL
}

nonisolated enum ProjectScaffoldError: Error, Sendable, Equatable {
    case directoryNotEmpty(URL)
    case missingAssets(URL)
}

// On any failure the freshly created tree is removed (best-effort) — it's ours,
// created fresh by this call.
nonisolated struct ProjectScaffolder {
    let assetsRoot: URL
    let overrides: ScaffoldOverrides
    let toggles: ScaffoldToggles
    let hookWirings: [HookWiring]
    let configCreator: ProjectConfigCreator
    let gitInitRunner: any GitInitializing
    let catalog: TemplateCatalog

    init(
        assetsRoot: URL = NewProjectAssets.bundledRoot,
        overrideRoot: URL? = ScaffoldOverrides.standardOverrideRoot(),
        toggles: ScaffoldToggles = .loadStandard(),
        hookWirings: [HookWiring] = HookWiringStore.loadStandard().wirings,
        configCreator: ProjectConfigCreator = ProjectConfigCreator(),
        gitInitRunner: any GitInitializing = GitInitRunner(),
        catalog: TemplateCatalog = .bundledDefault
    ) {
        self.assetsRoot = assetsRoot
        self.overrides = ScaffoldOverrides(bundledRoot: assetsRoot, overrideRoot: overrideRoot)
        self.toggles = toggles
        self.hookWirings = hookWirings
        self.configCreator = configCreator
        self.gitInitRunner = gitInitRunner
        self.catalog = catalog
    }

    // The bundled-or-user hooks enabled for a template: effective hooks plus
    // override-only `.sh` files, minus any disabled by the toggles.
    private func enabledHookNames(forTemplate templateID: String) -> [String] {
        let effective = catalog.effectiveHooks(forTemplate: templateID)
        let userHooks = overrides.overrideFileNames(inRelativeDir: "hooks")
            .filter { $0.hasSuffix(".sh") }
            .map { String($0.dropLast(3)) }
            .filter { !effective.contains($0) }
        return toggles.enabledNames(in: .hooks, from: effective + userHooks)
    }

    private var fileManager: FileManager { .default }

    func create(spec: NewProjectSpec) async throws -> CreatedProject {
        guard fileManager.fileExists(atPath: assetsRoot.path) else {
            throw ProjectScaffoldError.missingAssets(assetsRoot)
        }
        let root = spec.projectDirectory
        let preExisted = fileManager.fileExists(atPath: root.path)
        if preExisted {
            let contents = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
            guard !contents.contains(where: { $0 != ".DS_Store" }) else {
                throw ProjectScaffoldError.directoryNotEmpty(root)
            }
        } else {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }

        do {
            let bundle = try await build(spec: spec, root: root)
            return CreatedProject(root: root, bundle: bundle)
        } catch {
            cleanup(root: root, preExisted: preExisted)
            throw error
        }
    }

    private func build(spec: NewProjectSpec, root: URL) async throws -> URL {
        let claudeOutput = try ClaudeMdComposer(overrides: overrides, catalog: catalog).compose(spec: spec)

        let bundle = root.appending(path: "\(spec.name).plumage", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
        try configCreator.write(for: spec, toBundle: bundle)

        try writePlumageScripts(root: root)
        try writeClaudeTree(spec: spec, root: root, claudeOutput: claudeOutput)
        try writeMCPConfig(spec: spec, root: root)
        try writeSwiftConfigs(spec: spec, root: root)
        try writeGitignore(spec: spec, root: root)
        try await initGitIfRequested(spec: spec, root: root)
        return bundle
    }

    // MARK: - .plumage working dir

    private func writePlumageScripts(root: URL) throws {
        let scripts = root.appending(path: ".plumage/scripts", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        for script in overrides.unionFileNames(inRelativeDir: "plumage") {
            try copy(
                from: overrides.url(forRelative: "plumage/\(script)"),
                to: scripts.appending(path: script), executable: true)
        }
    }

    // MARK: - .claude tree

    private func writeClaudeTree(
        spec: NewProjectSpec, root: URL, claudeOutput: ClaudeMdComposer.Output
    )
        throws
    {
        let claude = root.appending(path: ".claude", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: claude, withIntermediateDirectories: true)

        try claudeOutput.claudeMd.write(
            to: claude.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)

        let docs = claude.appending(path: "docs", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: docs, withIntermediateDirectories: true)
        for doc in overrides.unionFileNames(inRelativeDir: "docs") {
            try copy(from: overrides.url(forRelative: "docs/\(doc)"), to: docs.appending(path: doc))
        }

        let issues = claude.appending(path: "issues", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: issues.appending(path: "archive", directoryHint: .isDirectory),
            withIntermediateDirectories: true)
        try copy(
            from: overrides.url(forRelative: "issues/_TEMPLATE.md"),
            to: issues.appending(path: "_TEMPLATE.md"))

        try writeSkills(spec: spec, claude: claude)
        try writeHooks(spec: spec, claude: claude)
        try writeAgents(claude: claude)
        try writeSettings(spec: spec, claude: claude)
    }

    // A user override of `.claude/settings.json` wins over generation (B2); the
    // minimal local settings file is always generated.
    private func writeSettings(spec: NewProjectSpec, claude: URL) throws {
        let composer = SettingsComposer(catalog: catalog)
        let data = try overrides.resolvedConfigData(forRelative: ".claude/settings.json") {
            try composer.settingsJSON(
                forTemplate: spec.templateID, toggles: toggles, userWirings: hookWirings)
        }
        try data.write(to: claude.appending(path: "settings.json"))
        try composer.localSettingsJSON().write(to: claude.appending(path: "settings.local.json"))
    }

    // The bundled skills plus any override-only (user-authored) skill directories.
    private var skillNames: [String] {
        let bundled = ScaffoldOverrides.bundledSkillNames
        let userSkills = overrides.overrideSkillDirNames().filter { !bundled.contains($0) }
        return bundled + userSkills
    }

    private func writeSkills(spec: NewProjectSpec, claude: URL) throws {
        let skillsDir = claude.appending(path: "skills", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skills = toggles.enabledNames(in: .skills, from: skillNames)
        for skill in skills {
            let dest = skillsDir.appending(path: skill, directoryHint: .isDirectory)
            try overrides.copyResolvedTree(relativeDir: "skills/\(skill)", to: dest)
            try ScaffoldOverrides.makeExecutable(
                scriptsIn: dest.appending(path: "scripts", directoryHint: .isDirectory))
        }
    }

    // First-time agent scaffolding: Plumage ships no agents, so the catalog is the
    // user's override `agents/` directory, filtered by the enable toggles. Written
    // unconditionally into a fresh tree (the scaffolder owns the directory).
    private func writeAgents(claude: URL) throws {
        let enabled = toggles.enabledNames(
            in: .agents, from: overrides.overrideFileNames(inRelativeDir: "agents"))
        guard !enabled.isEmpty else { return }
        let agentsDir = claude.appending(path: "agents", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        for name in enabled {
            try copy(
                from: overrides.url(forRelative: "agents/\(name)"),
                to: agentsDir.appending(path: name))
        }
    }

    private func writeHooks(spec: NewProjectSpec, claude: URL) throws {
        let hooksDir = claude.appending(path: "hooks", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        for hook in enabledHookNames(forTemplate: spec.templateID) {
            try copy(
                from: overrides.url(forRelative: "hooks/\(hook).sh"),
                to: hooksDir.appending(path: "\(hook).sh"),
                executable: true)
        }
    }

    // MARK: - root-level files

    // A user override of `.mcp.json` wins over generation (B2).
    private func writeMCPConfig(spec: NewProjectSpec, root: URL) throws {
        let data = try overrides.resolvedConfigData(forRelative: ".mcp.json") {
            try MCPConfigComposer(catalog: catalog).mcpJSON(forTemplate: spec.templateID)
        }
        try data.write(to: root.appending(path: ".mcp.json"))
    }

    private func writeSwiftConfigs(spec: NewProjectSpec, root: URL) throws {
        guard spec.kind.isSwift else { return }
        try copy(
            from: overrides.url(forRelative: "configs/swift-format"),
            to: root.appending(path: ".swift-format"))
        try copy(
            from: overrides.url(forRelative: "configs/swiftlint.yml"),
            to: root.appending(path: ".swiftlint.yml"))
    }

    private func writeGitignore(spec: NewProjectSpec, root: URL) throws {
        guard spec.git?.createGitignore == true else { return }
        // A user override of `.gitignore` wins over generation (B2): the manager edits
        // it as a global default, so a saved override is the user's chosen content.
        let data = try overrides.resolvedConfigData(forRelative: ".gitignore") {
            let text = try GitignoreComposer(overrides: overrides, catalog: catalog)
                .compose(forTemplate: spec.templateID)
            return Data(text.utf8)
        }
        try data.write(to: root.appending(path: ".gitignore"))
    }

    private func initGitIfRequested(spec: NewProjectSpec, root: URL) async throws {
        guard let git = spec.git else { return }
        try await gitInitRunner.initRepo(at: root, defaultBranch: "main")

        var excludes: [String] = []
        if !git.plumageInGit { excludes += [".plumage/", "\(spec.name).plumage/"] }
        if !git.claudeInGit { excludes += [".claude/", ".mcp.json"] }
        if !excludes.isEmpty {
            try GitExcludeWriter().append(paths: excludes, repoURL: root)
        }
    }

    // MARK: - helpers

    private func copy(from source: URL, to dest: URL, executable: Bool = false) throws {
        try fileManager.copyItem(at: source, to: dest)
        if executable { try ScaffoldOverrides.setExecutable(dest) }
    }

    private func cleanup(root: URL, preExisted: Bool) {
        if preExisted {
            let kids = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for kid in kids { try? fileManager.removeItem(at: kid) }
        } else {
            try? fileManager.removeItem(at: root)
        }
    }
}
