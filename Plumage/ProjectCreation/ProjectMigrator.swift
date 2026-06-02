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
    let name: String
    let tagline: String
    let git: MigrationGitSetup
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

    // The bundled-or-user hooks enabled for a kind: effective hooks plus override-only
    // `.sh` files, minus any disabled by the toggles.
    private func enabledHookNames(for kind: ProjectKind) -> [String] {
        let effective = catalog.effectiveHooks(forTemplate: kind.rawValue)
        let userHooks = overrides.overrideFileNames(inRelativeDir: "hooks")
            .filter { $0.hasSuffix(".sh") }
            .map { String($0.dropLast(3)) }
            .filter { !effective.contains($0) }
        return toggles.enabledNames(in: .hooks, from: effective + userHooks)
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

        try writePlumageScripts(root: root, into: &report)
        let bundle = try writeConfigBundle(
            spec: adapter, root: root, defaultBranch: defaultBranch, into: &report)
        try writeClaudeTree(spec: adapter, root: root, into: &report)
        try writeMCPConfig(spec: adapter, root: root, into: &report)
        try writeSwiftConfigs(spec: adapter, root: root, into: &report)
        try writeGitignore(spec: spec, root: root, into: &report)
        try await setupGit(spec: spec, root: root, repoState: repoState)

        return (
            CreatedProject(root: root, bundle: bundle),
            MigrationReport(added: report.added, skipped: report.skipped)
        )
    }

    // MARK: - tree

    private func writePlumageScripts(root: URL, into report: inout Report) throws {
        let scripts = root.appending(path: ".plumage/scripts", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        for script in overrides.unionFileNames(inRelativeDir: "plumage") {
            try copyIfMissing(
                from: overrides.url(forRelative: "plumage/\(script)"),
                to: scripts.appending(path: script),
                rel: ".plumage/scripts/\(script)", executable: true, into: &report)
        }
    }

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
        for doc in overrides.unionFileNames(inRelativeDir: "docs") {
            try copyIfMissing(
                from: overrides.url(forRelative: "docs/\(doc)"),
                to: docs.appending(path: doc), rel: ".claude/docs/\(doc)", into: &report)
        }

        let issues = claude.appending(path: "issues", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: issues.appending(path: "archive", directoryHint: .isDirectory),
            withIntermediateDirectories: true)
        try copyIfMissing(
            from: overrides.url(forRelative: "issues/_TEMPLATE.md"),
            to: issues.appending(path: "_TEMPLATE.md"),
            rel: ".claude/issues/_TEMPLATE.md", into: &report)

        try writeSkills(claude: claude, skillKeywords: claudeOutput.skillKeywords, into: &report)
        try writeHooks(spec: spec, claude: claude, into: &report)
        try writeAgents(claude: claude, into: &report)
        try writeSettings(kind: spec.kind, claude: claude, into: &report)
    }

    private static let bundledSkills = ["plumage-plan", "plumage-implement", "plumage-review"]
    private var skillNames: [String] {
        let userSkills = overrides.overrideSkillDirNames().filter { !Self.bundledSkills.contains($0) }
        return Self.bundledSkills + userSkills
    }

    private func writeSkills(claude: URL, skillKeywords: String, into report: inout Report) throws {
        let skillsDir = claude.appending(path: "skills", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skills = toggles.enabledNames(in: .skills, from: skillNames)
        for skill in skills {
            let dest = skillsDir.appending(path: skill, directoryHint: .isDirectory)
            let rel = ".claude/skills/\(skill)"
            if fileManager.fileExists(atPath: dest.path) {
                report.skipped.append(rel)
                continue
            }
            try copyResolvedTree(relativeDir: "skills/\(skill)", to: dest)
            let skillMd = dest.appending(path: "SKILL.md")
            let body = try String(contentsOf: skillMd, encoding: .utf8)
                .replacingOccurrences(of: "<<<SKILL_KEYWORDS>>>", with: skillKeywords)
            try body.write(to: skillMd, atomically: true, encoding: .utf8)
            try makeExecutable(scriptsIn: dest.appending(path: "scripts", directoryHint: .isDirectory))
            report.added.append(rel)
        }
    }

    private func writeHooks(spec: NewProjectSpec, claude: URL, into report: inout Report) throws {
        let hooksDir = claude.appending(path: "hooks", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        for hook in enabledHookNames(for: spec.kind) {
            try copyIfMissing(
                from: overrides.url(forRelative: "hooks/\(hook).sh"),
                to: hooksDir.appending(path: "\(hook).sh"),
                rel: ".claude/hooks/\(hook).sh", executable: true, into: &report)
        }
    }

    // Agents parity with the scaffolder, additive: each enabled user agent is
    // written only if it isn't already present in the target's `.claude/agents/`.
    private func writeAgents(claude: URL, into report: inout Report) throws {
        let enabled = toggles.enabledNames(
            in: .agents, from: overrides.overrideFileNames(inRelativeDir: "agents"))
        guard !enabled.isEmpty else { return }
        let agentsDir = claude.appending(path: "agents", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        for name in enabled {
            try copyIfMissing(
                from: overrides.url(forRelative: "agents/\(name)"),
                to: agentsDir.appending(path: name),
                rel: ".claude/agents/\(name)", into: &report)
        }
    }

    private func writeSettings(kind: ProjectKind, claude: URL, into report: inout Report) throws {
        let composer = SettingsComposer(catalog: catalog)
        try writeIfMissing(
            try composer.settingsJSON(for: kind, toggles: toggles, userWirings: hookWirings),
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
        var servers: [String: Any] = [:]
        for server in catalog.effectiveMCPServers(forTemplate: spec.kind.rawValue) {
            var entry: [String: Any] = ["command": server.command]
            if !server.args.isEmpty { entry["args"] = server.args }
            if !server.env.isEmpty { entry["env"] = server.env }
            servers[server.name] = entry
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["mcpServers": servers],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: dest, options: .atomic)
        report.added.append(".mcp.json")
    }

    private func writeSwiftConfigs(spec: NewProjectSpec, root: URL, into report: inout Report) throws {
        guard spec.kind.isSwift else { return }
        try copyIfMissing(
            from: overrides.url(forRelative: "configs/swift-format"),
            to: root.appending(path: ".swift-format"), rel: ".swift-format", into: &report)
        try copyIfMissing(
            from: overrides.url(forRelative: "configs/swiftlint.yml"),
            to: root.appending(path: ".swiftlint.yml"), rel: ".swiftlint.yml", into: &report)
    }

    private func writeGitignore(spec: MigrationSpec, root: URL, into report: inout Report) throws {
        guard spec.git.createGitignore else { return }
        let dest = root.appending(path: ".gitignore")
        if fileManager.fileExists(atPath: dest.path) {
            report.skipped.append(".gitignore")
            return
        }
        let contents = try GitignoreComposer(overrides: overrides, catalog: catalog).compose(for: spec.kind)
        try contents.write(to: dest, atomically: true, encoding: .utf8)
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
        if !spec.git.plumageInGit { excludes += [".plumage/", "\(spec.name).plumage/"] }
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
            kind: spec.kind, name: spec.name, tagline: spec.tagline,
            projectDirectory: spec.projectDirectory,
            git: GitSetup(
                plumageInGit: spec.git.plumageInGit,
                claudeInGit: spec.git.claudeInGit,
                createGitignore: spec.git.createGitignore))
    }

    // Copy a directory subtree into `dest`, resolving every regular file through the
    // override layer. The source tree defines the set of files: the bundled dir for a
    // bundled skill, or the override dir for a user-authored skill with no baseline.
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

    private func copyIfMissing(
        from source: URL, to dest: URL, rel: String, executable: Bool = false, into report: inout Report
    ) throws {
        if fileManager.fileExists(atPath: dest.path) {
            report.skipped.append(rel)
            return
        }
        try fileManager.copyItem(at: source, to: dest)
        if executable { try setExecutable(dest) }
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

    private func writeIfMissing(
        _ string: String, to dest: URL, rel: String, into report: inout Report
    )
        throws
    {
        try writeIfMissing(Data(string.utf8), to: dest, rel: rel, into: &report)
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
}
