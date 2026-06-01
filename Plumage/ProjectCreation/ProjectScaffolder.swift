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
    let configCreator: ProjectConfigCreator
    let gitInitRunner: any GitInitializing

    init(
        assetsRoot: URL = NewProjectAssets.bundledRoot,
        overrideRoot: URL? = ScaffoldOverrides.standardOverrideRoot(),
        configCreator: ProjectConfigCreator = ProjectConfigCreator(),
        gitInitRunner: any GitInitializing = GitInitRunner()
    ) {
        self.assetsRoot = assetsRoot
        self.overrides = ScaffoldOverrides(bundledRoot: assetsRoot, overrideRoot: overrideRoot)
        self.configCreator = configCreator
        self.gitInitRunner = gitInitRunner
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
        let claudeOutput = try ClaudeMdComposer(overrides: overrides).compose(spec: spec)

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
        try copy(
            from: overrides.url(forRelative: "plumage/roadmap.py"),
            to: scripts.appending(path: "roadmap.py"), executable: true)
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
        for doc in ["PROJECT.md", "notes.md", "decisions.md"] {
            try copy(from: overrides.url(forRelative: "docs/\(doc)"), to: docs.appending(path: doc))
        }

        let issues = claude.appending(path: "issues", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: issues.appending(path: "archive", directoryHint: .isDirectory),
            withIntermediateDirectories: true)
        try copy(
            from: overrides.url(forRelative: "issues/_TEMPLATE.md"),
            to: issues.appending(path: "_TEMPLATE.md"))

        try writeSkills(spec: spec, claude: claude, skillKeywords: claudeOutput.skillKeywords)
        try writeHooks(spec: spec, claude: claude)
        try SettingsComposer().write(for: spec.kind, toClaudeDir: claude)
    }

    private func writeSkills(spec: NewProjectSpec, claude: URL, skillKeywords: String) throws {
        let skillsDir = claude.appending(path: "skills", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        for skill in ["plumage-plan", "plumage-implement", "plumage-review"] {
            let dest = skillsDir.appending(path: skill, directoryHint: .isDirectory)
            try copyResolvedTree(relativeDir: "skills/\(skill)", to: dest)

            let skillMd = dest.appending(path: "SKILL.md")
            let body = try String(contentsOf: skillMd, encoding: .utf8)
                .replacingOccurrences(of: "<<<SKILL_KEYWORDS>>>", with: skillKeywords)
            try body.write(to: skillMd, atomically: true, encoding: .utf8)

            try makeExecutable(scriptsIn: dest.appending(path: "scripts", directoryHint: .isDirectory))
        }
    }

    private func writeHooks(spec: NewProjectSpec, claude: URL) throws {
        let hooksDir = claude.appending(path: "hooks", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        for hook in spec.kind.profile.hookNames {
            try copy(
                from: overrides.url(forRelative: "hooks/\(hook).sh"),
                to: hooksDir.appending(path: "\(hook).sh"),
                executable: true)
        }
    }

    // MARK: - root-level files

    private func writeMCPConfig(spec: NewProjectSpec, root: URL) throws {
        var servers: [String: Any] = [:]
        for server in spec.kind.profile.mcpServers {
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
        let contents = try GitignoreComposer(overrides: overrides).compose(for: spec.kind)
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

    // Copy a bundled directory subtree into `dest`, resolving every regular file
    // through the override layer. The bundled tree defines the set of files (an
    // override replaces a file's content, it never adds files to a skill); each
    // file is read from its override when present, else bundled.
    private func copyResolvedTree(relativeDir: String, to dest: URL) throws {
        let bundledDir = assetsRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        guard
            let enumerator = fileManager.enumerator(
                at: bundledDir, includingPropertiesForKeys: [.isRegularFileKey])
        else { return }
        for case let url as URL in enumerator {
            let isRegular = (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile ?? false
            guard isRegular else { continue }
            let suffix = url.standardizedFileURL.path
                .replacingOccurrences(of: bundledDir.standardizedFileURL.path + "/", with: "")
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
