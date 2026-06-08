import Foundation

nonisolated struct MigrationGitSetup: Hashable, Sendable {
    let initIfMissing: Bool
    let plumageInGit: Bool
    let claudeInGit: Bool
    let createGitignore: Bool

    init(
        initIfMissing: Bool = false,
        plumageInGit: Bool = true,
        claudeInGit: Bool = true,
        createGitignore: Bool = true
    ) {
        self.initIfMissing = initIfMissing
        self.plumageInGit = plumageInGit
        self.claudeInGit = claudeInGit
        self.createGitignore = createGitignore
    }
}

nonisolated struct MigrationSpec: Hashable, Sendable {
    let projectDirectory: URL
    let kind: ProjectKind
    // The catalog template to scaffold. Predefined ⇒ `kind.rawValue`; a custom
    // template carries its own id (and `kind` is `.other`). See `NewProjectSpec`.
    let templateID: String
    let name: String
    let tagline: String
    let git: MigrationGitSetup

    init(
        projectDirectory: URL, kind: ProjectKind, templateID: String? = nil,
        name: String, tagline: String, git: MigrationGitSetup
    ) {
        self.projectDirectory = projectDirectory
        self.kind = kind
        self.templateID = templateID ?? kind.rawValue
        self.name = name
        self.tagline = tagline
        self.git = git
    }
}

nonisolated struct MigrationReport: Hashable, Sendable {
    let added: [String]
    let skipped: [String]
}

nonisolated enum ProjectMigrateError: Error, Sendable, Equatable {
    case alreadyPlumage(URL)
    case missingAssets(URL)
    case directoryMissing(URL)
}

// Additive counterpart to `ProjectScaffolder`: turns an existing, possibly
// non-empty folder into an openable Plumage project by writing only what's
// missing. Never overwrites a pre-existing file, and never cleans up on
// failure — the directory isn't ours, so partial additions are left in place
// and the error is surfaced.
nonisolated struct ProjectMigrator {
    let assetsRoot: URL
    let overrides: ScaffoldOverrides
    let toggles: ScaffoldToggles
    let hookWirings: [HookWiring]
    let configCreator: ProjectConfigCreator
    let gitInitRunner: any GitInitializing
    let repoStateReader: RepoStateReader
    let catalog: TemplateCatalog

    init(
        assetsRoot: URL = NewProjectAssets.bundledRoot,
        overrideRoot: URL? = ScaffoldOverrides.standardOverrideRoot(),
        toggles: ScaffoldToggles = .loadStandard(),
        hookWirings: [HookWiring] = HookWiringStore.loadStandard().wirings,
        configCreator: ProjectConfigCreator = ProjectConfigCreator(),
        gitInitRunner: any GitInitializing = GitInitRunner(),
        repoStateReader: RepoStateReader = RepoStateReader(),
        catalog: TemplateCatalog = .bundledDefault
    ) {
        self.assetsRoot = assetsRoot
        self.overrides = ScaffoldOverrides(bundledRoot: assetsRoot, overrideRoot: overrideRoot)
        self.toggles = toggles
        self.hookWirings = hookWirings
        self.configCreator = configCreator
        self.gitInitRunner = gitInitRunner
        self.repoStateReader = repoStateReader
        self.catalog = catalog
    }

    // The bundled-or-user hooks enabled for a template, as (base name, real filename)
    // pairs. Built-ins resolve to `<base>.sh`; a user override hook keeps its real
    // extension (e.g. `.py`). The toggle key stays the base name — built-ins toggle by
    // base — so recognition is extension-agnostic while identity is unchanged.
    private func enabledHookFiles(forTemplate templateID: String) -> [(base: String, fileName: String)] {
        let effective = catalog.effectiveHooks(forTemplate: templateID)
        var fileByBase: [String: String] = [:]
        for base in effective { fileByBase[base] = "\(base).sh" }
        var userBases: [String] = []
        for file in overrides.overrideFileNames(inRelativeDir: "hooks") {
            let base = (file as NSString).deletingPathExtension
            if fileByBase[base] == nil { userBases.append(base) }
            fileByBase[base] = file  // the real override file wins, carrying its extension
        }
        return toggles.enabledNames(in: .hooks, from: effective + userBases)
            .map { ($0, fileByBase[$0] ?? "\($0).sh") }
    }

    private var fileManager: FileManager { .default }

    func migrate(spec: MigrationSpec) async throws -> (CreatedProject, MigrationReport) {
        guard fileManager.fileExists(atPath: assetsRoot.path) else {
            throw ProjectMigrateError.missingAssets(assetsRoot)
        }
        let root = spec.projectDirectory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw ProjectMigrateError.directoryMissing(root)
        }
        if let bundle = existingBundle(in: root) {
            throw ProjectMigrateError.alreadyPlumage(bundle)
        }

        let repoState = repoStateReader.read(repoURL: root)
        let defaultBranch = repoState.branchName ?? "main"
        let adapter = newProjectSpec(from: spec)
        var report = Report()

        let bundle = try writeConfigBundle(
            spec: adapter, root: root, defaultBranch: defaultBranch, into: &report)
        try writeClaudeTree(spec: adapter, root: root, into: &report)
        try writeMCPConfig(spec: adapter, root: root, into: &report)
        try writeSwiftConfigs(spec: adapter, root: root, into: &report)
        try writeGitignore(spec: spec, root: root, into: &report)
        try writeArbitraryFiles(spec: adapter, root: root, into: &report)
        try await setupGit(spec: spec, root: root, repoState: repoState)

        return (
            CreatedProject(root: root, bundle: bundle),
            MigrationReport(added: report.added, skipped: report.skipped)
        )
    }

    // MARK: - tree

    private func writeConfigBundle(
        spec: NewProjectSpec, root: URL, defaultBranch: String, into report: inout Report
    ) throws -> URL {
        let bundle = root.appending(path: "\(spec.name).plumage", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
        try configCreator.write(for: spec, toBundle: bundle, defaultBranch: defaultBranch)
        report.added.append("\(spec.name).plumage/config.json")
        return bundle
    }

    private func writeClaudeTree(spec: NewProjectSpec, root: URL, into report: inout Report) throws {
        let claude = root.appending(path: ".claude", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: claude, withIntermediateDirectories: true)

        let claudeOutput = try ClaudeMdComposer(overrides: overrides, catalog: catalog).compose(spec: spec)
        try writeIfMissing(
            claudeOutput.claudeMd, to: claude.appending(path: "CLAUDE.md"),
            rel: ".claude/CLAUDE.md", into: &report)

        let docs = claude.appending(path: "docs", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: docs, withIntermediateDirectories: true)
        let roots = catalog.looseSurfaceRoots(forTemplate: spec.templateID)
        for (name, variants) in overrides.composedLooseFileVariants(category: "docs", roots: roots) {
            try writeResolvedIfMissing(
                variants, to: docs.appending(path: name), rel: ".claude/docs/\(name)", into: &report)
        }

        let issues = claude.appending(path: "issues", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: issues.appending(path: "archive", directoryHint: .isDirectory),
            withIntermediateDirectories: true)
        try copyIfMissing(
            from: overrides.url(forRelative: "issues/_TEMPLATE.md"),
            to: issues.appending(path: "_TEMPLATE.md"),
            rel: ".claude/issues/_TEMPLATE.md", into: &report)

        try writeSkills(templateID: spec.templateID, claude: claude, into: &report)
        try writeHooks(spec: spec, claude: claude, into: &report)
        try writeAgents(templateID: spec.templateID, claude: claude, into: &report)
        try writeSettings(templateID: spec.templateID, claude: claude, into: &report)
    }

    private func writeSkills(templateID: String, claude: URL, into report: inout Report) throws {
        let skillsDir = claude.appending(path: "skills", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        // Base ∪ template ∪ member-component skills, most-specific scope winning; the
        // winning source is resolved first, then written only if the target is absent.
        let composed = overrides.composedSkillDirs(
            roots: catalog.looseSurfaceRoots(forTemplate: templateID))
        let enabled = Set(toggles.enabledNames(in: .skills, from: composed.map(\.name)))
        for (name, relDir) in composed where enabled.contains(name) {
            let dest = skillsDir.appending(path: name, directoryHint: .isDirectory)
            let rel = ".claude/skills/\(name)"
            if fileManager.fileExists(atPath: dest.path) {
                report.skipped.append(rel)
                continue
            }
            try overrides.copyResolvedTree(relativeDir: relDir, to: dest)
            try ScaffoldOverrides.makeExecutable(
                scriptsIn: dest.appending(path: "scripts", directoryHint: .isDirectory))
            report.added.append(rel)
        }
    }

    // Reproduce the user's hand-built loose tree (files outside the typed/composition
    // namespaces) at their project-relative positions, additively (#00078).
    private func writeArbitraryFiles(spec: NewProjectSpec, root: URL, into report: inout Report) throws {
        let roots = catalog.looseSurfaceRoots(forTemplate: spec.templateID)
        for (output, variants) in overrides.composedArbitraryFileVariants(roots: roots) {
            let dest = root.appending(path: output)
            try fileManager.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeResolvedIfMissing(variants, to: dest, rel: output, into: &report)
        }
    }

    private func writeHooks(spec: NewProjectSpec, claude: URL, into report: inout Report) throws {
        let hooksDir = claude.appending(path: "hooks", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        for hook in enabledHookFiles(forTemplate: spec.templateID) {
            try copyIfMissing(
                from: overrides.url(forRelative: "hooks/\(hook.fileName)"),
                to: hooksDir.appending(path: hook.fileName),
                rel: ".claude/hooks/\(hook.fileName)", executable: true, into: &report)
        }
    }

    // Agents parity with the scaffolder, additive: each enabled user agent (composed
    // across the template's loose roots, #00078) is written only if it isn't already
    // present in the target's `.claude/agents/`.
    private func writeAgents(templateID: String, claude: URL, into report: inout Report) throws {
        let composed = overrides.composedLooseFileVariants(
            category: "agents", roots: catalog.looseSurfaceRoots(forTemplate: templateID))
        let enabled = Set(toggles.enabledNames(in: .agents, from: composed.map(\.name)))
        let selected = composed.filter { enabled.contains($0.name) }
        guard !selected.isEmpty else { return }
        let agentsDir = claude.appending(path: "agents", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        for (name, variants) in selected {
            try writeResolvedIfMissing(
                variants, to: agentsDir.appending(path: name),
                rel: ".claude/agents/\(name)", into: &report)
        }
    }

    private func writeSettings(templateID: String, claude: URL, into report: inout Report) throws {
        let composer = SettingsComposer(catalog: catalog)
        // A user override wins over generation (B2), same as the scaffolder.
        let settingsData = try overrides.resolvedConfigData(forRelative: ".claude/settings.json") {
            try composer.settingsJSON(
                forTemplate: templateID, toggles: toggles, userWirings: hookWirings)
        }
        try writeIfMissing(
            settingsData,
            to: claude.appending(path: "settings.json"),
            rel: ".claude/settings.json", into: &report)
        try writeIfMissing(
            composer.localSettingsJSON(), to: claude.appending(path: "settings.local.json"),
            rel: ".claude/settings.local.json", into: &report)
    }

    private func writeMCPConfig(spec: NewProjectSpec, root: URL, into report: inout Report) throws {
        let dest = root.appending(path: ".mcp.json")
        if fileManager.fileExists(atPath: dest.path) {
            report.skipped.append(".mcp.json")
            return
        }
        let data = try overrides.resolvedConfigData(forRelative: ".mcp.json") {
            try MCPConfigComposer(catalog: catalog).mcpJSON(forTemplate: spec.templateID)
        }
        try data.write(to: dest, options: .atomic)
        report.added.append(".mcp.json")
    }

    private func writeSwiftConfigs(spec: NewProjectSpec, root: URL, into report: inout Report) throws {
        for name in catalog.effectiveConfigs(forTemplate: spec.templateID) {
            try copyIfMissing(
                from: overrides.url(forRelative: "configs/\(name)"),
                to: root.appending(path: ".\(name)"), rel: ".\(name)", into: &report)
        }
    }

    private func writeGitignore(spec: MigrationSpec, root: URL, into report: inout Report) throws {
        guard spec.git.createGitignore else { return }
        let dest = root.appending(path: ".gitignore")
        if fileManager.fileExists(atPath: dest.path) {
            report.skipped.append(".gitignore")
            return
        }
        let data = try overrides.resolvedConfigData(forRelative: ".gitignore") {
            let text = try GitignoreComposer(overrides: overrides, catalog: catalog)
                .compose(forTemplate: spec.templateID)
            return Data(text.utf8)
        }
        try data.write(to: dest, options: .atomic)
        report.added.append(".gitignore")
    }

    private func setupGit(spec: MigrationSpec, root: URL, repoState: RepoState) async throws {
        var hasRepo = repoState.isGitRepo
        if !hasRepo, spec.git.initIfMissing {
            try await gitInitRunner.initRepo(at: root, defaultBranch: "main")
            hasRepo = true
        }
        guard hasRepo else { return }

        var excludes: [String] = []
        if !spec.git.plumageInGit { excludes += ["\(spec.name).plumage/"] }
        if !spec.git.claudeInGit { excludes += [".claude/", ".mcp.json"] }
        if !excludes.isEmpty {
            try GitExcludeWriter().append(paths: excludes, repoURL: root)
        }
    }

    // MARK: - helpers

    private struct Report {
        var added: [String] = []
        var skipped: [String] = []
    }

    private func existingBundle(in root: URL) -> URL? {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents.first { $0.pathExtension == BundleResolver.bundleExtension }
    }

    private func newProjectSpec(from spec: MigrationSpec) -> NewProjectSpec {
        NewProjectSpec(
            kind: spec.kind, templateID: spec.templateID, name: spec.name, tagline: spec.tagline,
            projectDirectory: spec.projectDirectory,
            git: GitSetup(
                plumageInGit: spec.git.plumageInGit,
                claudeInGit: spec.git.claudeInGit,
                createGitignore: spec.git.createGitignore))
    }

    private func copyIfMissing(
        from source: URL, to dest: URL, rel: String, executable: Bool = false, into report: inout Report
    ) throws {
        if fileManager.fileExists(atPath: dest.path) {
            report.skipped.append(rel)
            return
        }
        try fileManager.copyItem(at: source, to: dest)
        if executable { try ScaffoldOverrides.setExecutable(dest) }
        report.added.append(rel)
    }

    private func writeIfMissing(
        _ data: Data, to dest: URL, rel: String, into report: inout Report
    )
        throws
    {
        if fileManager.fileExists(atPath: dest.path) {
            report.skipped.append(rel)
            return
        }
        try data.write(to: dest, options: .atomic)
        report.added.append(rel)
    }

    // Resolve same-named loose-file `variants` (placeholder merge or file-level winner)
    // and write the result only if the target is absent — additive, same as a copy.
    private func writeResolvedIfMissing(
        _ variants: [String], to dest: URL, rel: String, into report: inout Report
    ) throws {
        if fileManager.fileExists(atPath: dest.path) {
            report.skipped.append(rel)
            return
        }
        try overrides.resolveLooseFile(variants: variants).write(to: dest, using: fileManager)
        report.added.append(rel)
    }

    private func writeIfMissing(
        _ string: String, to dest: URL, rel: String, into report: inout Report
    )
        throws
    {
        try writeIfMissing(Data(string.utf8), to: dest, rel: rel, into: &report)
    }
}
