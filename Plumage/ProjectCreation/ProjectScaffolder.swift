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
        if overrides.hasOverride(forRelative: ".claude/settings.json") {
            try overrides.data(atRelative: ".claude/settings.json").write(
                to: claude.appending(path: "settings.json"))
            try composer.localSettingsJSON().write(to: claude.appending(path: "settings.local.json"))
        } else {
            try composer.write(
                forTemplate: spec.templateID, toggles: toggles, userWirings: hookWirings,
                toClaudeDir: claude)
        }
    }

    // The bundled skills plus any override-only (user-authored) skill directories.
    private static let bundledSkills = ["plumage-plan", "plumage-implement", "plumage-review"]
    private var skillNames: [String] {
        let userSkills = overrides.overrideSkillDirNames().filter { !Self.bundledSkills.contains($0) }
        return Self.bundledSkills + userSkills
    }

    private func writeSkills(spec: NewProjectSpec, claude: URL) throws {
        let skillsDir = claude.appending(path: "skills", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skills = toggles.enabledNames(in: .skills, from: skillNames)
        for skill in skills {
            let dest = skillsDir.appending(path: skill, directoryHint: .isDirectory)
            try copyResolvedTree(relativeDir: "skills/\(skill)", to: dest)
            try makeExecutable(scriptsIn: dest.appending(path: "scripts", directoryHint: .isDirectory))
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

    private func writeMCPConfig(spec: NewProjectSpec, root: URL) throws {
        // A user override of `.mcp.json` wins over generation (B2).
        if overrides.hasOverride(forRelative: ".mcp.json") {
            try overrides.data(atRelative: ".mcp.json").write(to: root.appending(path: ".mcp.json"))
            return
        }
        var servers: [String: Any] = [:]
        for server in catalog.effectiveMCPServers(forTemplate: spec.templateID) {
            var entry: [String: Any] = ["command": server.command]
            if !server.args.isEmpty { entry["args"] = server.args }
            if !server.env.isEmpty { entry["env"] = server.env }
            servers[server.name] = entry
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["mcpServers": servers],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
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
        let contents =
            overrides.hasOverride(forRelative: ".gitignore")
            ? try overrides.string(atRelative: ".gitignore")
            : try GitignoreComposer(overrides: overrides, catalog: catalog)
                .compose(forTemplate: spec.templateID)
        try contents.write(to: root.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
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
        if executable { try setExecutable(dest) }
    }

    // Copy a directory subtree into `dest`, resolving every regular file through the
    // override layer. The source tree defines the set of files: the bundled dir for a
    // bundled skill (an override replaces a file's content, never adds files), or the
    // override dir for a user-authored skill that has no bundled baseline.
    private func copyResolvedTree(relativeDir: String, to dest: URL) throws {
        let bundledDir = assetsRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        let sourceDir =
            fileManager.fileExists(atPath: bundledDir.path)
            ? bundledDir : (overrides.overrideURL(forRelative: relativeDir) ?? bundledDir)
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        guard
            let enumerator = fileManager.enumerator(
                at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey])
        else { return }
        for case let url as URL in enumerator {
            let isRegular = (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile ?? false
            guard isRegular else { continue }
            let suffix = url.standardizedFileURL.path
                .replacingOccurrences(of: sourceDir.standardizedFileURL.path + "/", with: "")
            let resolved = overrides.url(forRelative: "\(relativeDir)/\(suffix)")
            let target = dest.appending(path: suffix)
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: resolved, to: target)
        }
    }

    private func setExecutable(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeExecutable(scriptsIn dir: URL) throws {
        guard fileManager.fileExists(atPath: dir.path) else { return }
        for entry in try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where entry.pathExtension == "sh" || entry.pathExtension == "py" {
            try setExecutable(entry)
        }
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
