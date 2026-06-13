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

    // The hooks enabled for a template, as (base name, store path) pairs: built-ins
    // (a content override wins by stem, carrying its extension) plus the template's
    // scope-owned user hooks. The toggle key stays the base name.
    private func enabledHookFiles(forTemplate templateID: String) -> [(base: String, relativePath: String)] {
        let effective = catalog.effectiveHooks(forTemplate: templateID)
        var pathByBase: [String: String] = [:]
        for base in effective { pathByBase[base] = "hooks/\(base).sh" }
        for file in overrides.overrideFileNames(inRelativeDir: "hooks") {
            let base = (file as NSString).deletingPathExtension
            if pathByBase[base] != nil { pathByBase[base] = "hooks/\(file)" }
        }
        let effectiveSet = Set(effective)
        let userHooks = catalog.effectiveUserHooks(forTemplate: templateID, overrides: overrides)
            .filter { !effectiveSet.contains($0.base) }
        for hook in userHooks { pathByBase[hook.base] = hook.relativePath }
        return toggles.enabledNames(in: .hooks, from: effective + userHooks.map(\.base))
            .map { ($0, pathByBase[$0] ?? "hooks/\($0).sh") }
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

        try writeClaudeTree(spec: spec, root: root, claudeOutput: claudeOutput)
        try writeMCPConfig(spec: spec, root: root)
        try writeSwiftConfigs(spec: spec, root: root)
        try writeGitignore(spec: spec, root: root)
        try writeArbitraryFiles(spec: spec, root: root)
        try await initGitIfRequested(spec: spec, root: root)
        return bundle
    }

    // Reproduce the user's hand-built loose tree — files outside the typed/composition
    // namespaces, at their project-relative positions, composed across the template's
    // scope roots. Generated configs already written win a name clash.
    private func writeArbitraryFiles(spec: NewProjectSpec, root: URL) throws {
        let roots = catalog.looseSurfaceRoots(forTemplate: spec.templateID)
        for (output, variants) in overrides.composedArbitraryFileVariants(roots: roots) {
            let dest = root.appending(path: output)
            guard !fileManager.fileExists(atPath: dest.path) else { continue }
            try fileManager.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try overrides.resolveLooseFile(variants: variants).write(to: dest, using: fileManager)
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
        let roots = catalog.looseSurfaceRoots(forTemplate: spec.templateID)
        for (name, variants) in overrides.composedLooseFileVariants(category: "docs", roots: roots) {
            try overrides.resolveLooseFile(variants: variants)
                .write(to: docs.appending(path: name), using: fileManager)
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
        try writeAgents(templateID: spec.templateID, claude: claude)
        try writeSettings(spec: spec, claude: claude)
    }

    // A user override of `.claude/settings.json` wins over generation (B2); the
    // minimal local settings file is always generated.
    private func writeSettings(spec: NewProjectSpec, claude: URL) throws {
        let composer = SettingsComposer(catalog: catalog, overrides: overrides)
        let data = try overrides.resolvedConfigData(forRelative: ".claude/settings.json") {
            try composer.settingsJSON(
                forTemplate: spec.templateID, toggles: toggles, userWirings: hookWirings)
        }
        try data.write(to: claude.appending(path: "settings.json"))
        try composer.localSettingsJSON().write(to: claude.appending(path: "settings.local.json"))
    }

    private func writeSkills(spec: NewProjectSpec, claude: URL) throws {
        let skillsDir = claude.appending(path: "skills", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        // Base ∪ template ∪ member-component skills, most-specific scope winning.
        let composed = overrides.composedSkillDirs(
            roots: catalog.looseSurfaceRoots(forTemplate: spec.templateID))
        let enabled = Set(toggles.enabledNames(in: .skills, from: composed.map(\.name)))
        for (name, relDir) in composed where enabled.contains(name) {
            let dest = skillsDir.appending(path: name, directoryHint: .isDirectory)
            try overrides.copyResolvedTree(relativeDir: relDir, to: dest)
            try ScaffoldOverrides.makeExecutable(
                scriptsIn: dest.appending(path: "scripts", directoryHint: .isDirectory))
        }
    }

    // First-time agent scaffolding: Plumage ships no agents, so the catalog is the user's
    // scope-owned `agents/` files unioned across the template's loose roots,
    // filtered by the enable toggles. Written into a fresh tree (the scaffolder owns it).
    private func writeAgents(templateID: String, claude: URL) throws {
        let composed = overrides.composedLooseFileVariants(
            category: "agents", roots: catalog.looseSurfaceRoots(forTemplate: templateID))
        let enabled = Set(toggles.enabledNames(in: .agents, from: composed.map(\.name)))
        let selected = composed.filter { enabled.contains($0.name) }
        guard !selected.isEmpty else { return }
        let agentsDir = claude.appending(path: "agents", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        for (name, variants) in selected {
            try overrides.resolveLooseFile(variants: variants)
                .write(to: agentsDir.appending(path: name), using: fileManager)
        }
    }

    private func writeHooks(spec: NewProjectSpec, claude: URL) throws {
        let hooksDir = claude.appending(path: "hooks", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        for hook in enabledHookFiles(forTemplate: spec.templateID) {
            let fileName = (hook.relativePath as NSString).lastPathComponent
            try copy(
                from: overrides.url(forRelative: hook.relativePath),
                to: hooksDir.appending(path: fileName),
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

    // Membership, not a hardcoded `isSwift`, decides which configs land — mirroring hooks.
    private func writeSwiftConfigs(spec: NewProjectSpec, root: URL) throws {
        for name in catalog.effectiveConfigs(forTemplate: spec.templateID) {
            try copy(
                from: overrides.url(forRelative: "configs/\(name)"),
                to: root.appending(path: ".\(name)"))
        }
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
        if git.plumageInGit {
            excludes += GitExcludeWriter.plumageEphemeralPaths
        } else {
            excludes += ["\(spec.name).plumage/"]
            try excludeBundleFromSwiftLint(name: spec.name, root: root)
        }
        if !git.claudeInGit { excludes += [".claude/", ".mcp.json"] }
        if !excludes.isEmpty {
            try GitExcludeWriter().append(paths: excludes, repoURL: root)
        }
    }

    // No-op when the template wrote no .swiftlint.yml (non-Swift); the entry
    // mirrors the bundle's .git/info/exclude line so neither tool scans it.
    private func excludeBundleFromSwiftLint(name: String, root: URL) throws {
        let configURL = root.appending(path: ".swiftlint.yml")
        guard let yaml = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        let updated = SwiftLintConfigEditor.addingExclude("\(name).plumage/", to: yaml)
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
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
