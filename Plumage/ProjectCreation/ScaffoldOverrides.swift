import Foundation
import os

// Per-file override layer: each path resolves to the user's override copy when present,
// else the bundled original — per-file (not per-directory) so an override is never
// all-or-nothing. The store lives under Application Support, never the Claude config
// directory, so the ClaudeCodeIntegration boundary stays intact.
nonisolated enum ScaffoldOverridesError: Error, Equatable {
    case noOverrideStore
    case escapesStore(String)

    var localizedDescription: String {
        switch self {
        case .noOverrideStore:
            return "No override store is available."
        case .escapesStore(let path):
            return "The path \"\(path)\" escapes the override store."
        }
    }
}

nonisolated struct ScaffoldOverrides: Sendable {
    let bundledRoot: URL
    let overrideRoot: URL?

    init(
        bundledRoot: URL = NewProjectAssets.bundledRoot,
        overrideRoot: URL? = nil
    ) {
        self.bundledRoot = bundledRoot
        self.overrideRoot = overrideRoot
    }

    // The user's override store under Application Support, mirroring the bundled
    // tree flat. Computed but not created here — it materializes when the editor
    // first writes an override. nil only if Application Support is unreachable.
    static func standardOverrideRoot() -> URL? {
        try? ApplicationSupport.appFolderURL()
            .appending(path: NewProjectAssets.folderName, directoryHint: .isDirectory)
    }

    // The standard resolver: bundled assets overlaid by the user's store.
    static func standard(
        bundledRoot: URL = NewProjectAssets.bundledRoot
    ) -> ScaffoldOverrides {
        ScaffoldOverrides(bundledRoot: bundledRoot, overrideRoot: standardOverrideRoot())
    }

    // Single source of truth for a layer's store path so
    // the composer, manager, scaffolder and migration can't drift between read and write.
    static func layerRelativePath(_ layer: String) -> String { "templates/\(layer)/CLAUDE.md" }

    func url(forRelative relativePath: String) -> URL {
        if let override = overrideURL(forRelative: relativePath),
            FileManager.default.fileExists(atPath: override.path)
        {
            return override
        }
        return bundledRoot.appending(path: relativePath)
    }

    func data(atRelative relativePath: String) throws -> Data {
        try Data(contentsOf: url(forRelative: relativePath))
    }

    func string(atRelative relativePath: String) throws -> String {
        try String(contentsOf: url(forRelative: relativePath), encoding: .utf8)
    }

    // The override slot for a relative path (whether or not a file is present),
    // or nil when no override store is configured.
    func overrideURL(forRelative relativePath: String) -> URL? {
        overrideRoot?.appending(path: relativePath)
    }

    func hasOverride(forRelative relativePath: String) -> Bool {
        guard let override = overrideURL(forRelative: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: override.path)
    }

    // Whether a bundled original exists for this path. Drives the editor's
    // "Reset to default" (bundled-backed) vs "Delete" (user-authored) choice.
    func hasBundledOriginal(forRelative relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: bundledRoot.appending(path: relativePath).path)
    }

    // Whether the override at `relativePath` actually diverges from the bundled
    // original. A user-authored file (no bundled baseline) counts as overridden
    // whenever its override exists; an override byte-identical to bundled does not.
    // Drives the ● "overridden" marker.
    func isContentOverridden(forRelative relativePath: String) -> Bool {
        guard hasOverride(forRelative: relativePath),
            let overrideURL = overrideURL(forRelative: relativePath)
        else { return false }
        let bundled = bundledRoot.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: bundled.path) else { return true }
        // Cheap reject first: differing sizes can't be byte-identical, so skip reading.
        if let bundledSize = Self.fileSize(bundled), let overrideSize = Self.fileSize(overrideURL),
            bundledSize != overrideSize
        {
            return true
        }
        guard let bundledData = try? Data(contentsOf: bundled) else { return true }
        let overrideData = (try? Data(contentsOf: overrideURL)) ?? Data()
        return overrideData != bundledData
    }

    private static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    // User override wins over generation (B2). The single decision point both config
    // writers share, so scaffold and migrate can't disagree on precedence.
    func resolvedConfigData(forRelative relativePath: String, generate: () throws -> Data) throws -> Data {
        hasOverride(forRelative: relativePath) ? try data(atRelative: relativePath) : try generate()
    }

    // MARK: - Write path

    // Materialize an override at `relativePath` with the given bytes, creating the
    // store and any intermediate directories. Atomic, so a concurrent scaffold reads
    // either the old or the new file, never a partial one. The returned URL is the
    // override slot (where the bytes now live).
    @discardableResult
    func writeOverride(_ data: Data, toRelative relativePath: String) throws -> URL {
        let target = try overrideTarget(forRelative: relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return target
    }

    @discardableResult
    func writeOverride(_ string: String, toRelative relativePath: String) throws -> URL {
        try writeOverride(Data(string.utf8), toRelative: relativePath)
    }

    // Remove the override at `relativePath` (revert-to-bundled for a bundled-backed
    // file, or outright delete for a user-authored one). Idempotent: a missing
    // override is a no-op. Prunes now-empty ancestor directories up to the store
    // root so the override tree stays byte-identical to "no override" when emptied.
    func removeOverride(forRelative relativePath: String) throws {
        guard let overrideRoot else { return }
        let target = try overrideTarget(forRelative: relativePath)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
        pruneEmptyDirectories(from: target.deletingLastPathComponent(), upTo: overrideRoot)
    }

    private func overrideTarget(forRelative relativePath: String) throws -> URL {
        guard let overrideRoot else { throw ScaffoldOverridesError.noOverrideStore }
        let target = overrideRoot.appending(path: relativePath)
        let rootPath = overrideRoot.standardizedFileURL.path
        guard target.standardizedFileURL.path.hasPrefix(rootPath + "/") else {
            throw ScaffoldOverridesError.escapesStore(relativePath)
        }
        return target
    }

    private func pruneEmptyDirectories(from directory: URL, upTo root: URL) {
        let fileManager = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var dir = directory
        while dir.standardizedFileURL.path.hasPrefix(rootPath + "/") {
            let contents = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
            guard contents.isEmpty else { break }
            try? fileManager.removeItem(at: dir)
            dir = dir.deletingLastPathComponent()
        }
    }

    // MARK: - Tombstones (suppressed bundled files)

    // A bundled file the user moves away can't be "deleted" the usual way —
    // `removeOverride` only reverts to bundled, and the bytes live in the read-only app
    // bundle. A tombstone records the bundled relativePath as suppressed so it stops
    // surfacing at its original location. Persisted as a JSON string array in
    // `tombstones.json` at the store root, read on demand to keep this struct stateless.
    // (The tree walks exclude this file via `typedStoreTopLevel`.)
    static let tombstonesFileName = "tombstones.json"

    private var tombstonesURL: URL? {
        overrideRoot?.appending(path: Self.tombstonesFileName)
    }

    func suppressedRelativePaths() -> Set<String> {
        guard let tombstonesURL,
            FileManager.default.fileExists(atPath: tombstonesURL.path)
        else { return [] }
        do {
            let data = try Data(contentsOf: tombstonesURL)
            return Set(try JSONDecoder().decode([String].self, from: data))
        } catch {
            // Empty set is also the legitimate "no tombstones" answer — a
            // corrupt file silently resurrecting suppressed scaffold entries
            // must at least leave a trace.
            Logger(subsystem: "com.plumage", category: "ScaffoldOverrides").error(
                "tombstones.json unreadable: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func isSuppressed(relativePath: String) -> Bool {
        suppressedRelativePaths().contains(relativePath)
    }

    func suppress(relativePath: String) throws {
        guard let overrideRoot, let tombstonesURL else {
            throw ScaffoldOverridesError.noOverrideStore
        }
        var set = suppressedRelativePaths()
        guard set.insert(relativePath).inserted else { return }
        try FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(set.sorted()).write(to: tombstonesURL, options: .atomic)
    }

    func unsuppress(relativePath: String) throws {
        guard let tombstonesURL else { return }
        var set = suppressedRelativePaths()
        guard set.remove(relativePath) != nil else { return }
        // Keep "no tombstones == byte-identical to a fresh store": drop the file when empty.
        guard !set.isEmpty else {
            try? FileManager.default.removeItem(at: tombstonesURL)
            return
        }
        try JSONEncoder().encode(set.sorted()).write(to: tombstonesURL, options: .atomic)
    }

    // Lift every tombstone at once (Restore Defaults), removing the store file entirely.
    func clearTombstones() {
        guard let tombstonesURL else { return }
        try? FileManager.default.removeItem(at: tombstonesURL)
    }

    // MARK: - Factory reset

    // Trashes the whole store rather than deleting it, so a factory reset stays
    // recoverable — mirroring custom-item delete (per-file `removeOverride` reverts
    // only one bundled-backed file and can't drop user-authored ones).
    func trashEntireStore() throws {
        guard let overrideRoot else { throw ScaffoldOverridesError.noOverrideStore }
        guard FileManager.default.fileExists(atPath: overrideRoot.path) else { return }
        try FileManager.default.trashItem(at: overrideRoot, resultingItemURL: nil)
    }

    // File names directly inside the override `<relativeDir>` directory, sorted.
    // Used for catalogs that have no bundled baseline (user-authored agents):
    // the set of files is whatever the user created. Empty when there is no
    // override store or the directory is absent.
    func overrideFileNames(inRelativeDir relativeDir: String) -> [String] {
        guard let overrideRoot else { return [] }
        let dir = overrideRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        return Self.regularFileNames(in: dir).sorted()
    }

    // Union of regular file names in the bundled and override copies of
    // `relativeDir`, sorted and de-duplicated. Used by catalogs and writers that
    // combine the bundled baseline with user-authored override-only files. With no
    // override store this is exactly the bundled set (byte-identical default).
    func unionFileNames(inRelativeDir relativeDir: String) -> [String] {
        let bundledDir = bundledRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        var names = Set(Self.regularFileNames(in: bundledDir))
        names.formUnion(overrideFileNames(inRelativeDir: relativeDir))
        let suppressed = suppressedRelativePaths()
        return names.filter { !suppressed.contains("\(relativeDir)/\($0)") }.sorted()
    }

    // Top-level directory names under the override `<root>/skills/` that contain a
    // `SKILL.md` — i.e. user-authored skills (and any bundled skill the user has
    // overridden). `inRoot` scopes the lookup to a manager tier's subtree;
    // empty (the default) is the historical store-root behaviour. Empty with no store.
    func overrideSkillDirNames(inRoot root: String = "") -> [String] {
        guard let overrideRoot else { return [] }
        let skillsRel = root.isEmpty ? "skills" : "\(root)/skills"
        let skillsDir = overrideRoot.appending(path: skillsRel, directoryHint: .isDirectory)
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "SKILL.md").path) }
            .map(\.lastPathComponent)
            .sorted()
    }

    // Regular file sub-paths (relative to `relativeDir`) found recursively in the
    // override copy of `relativeDir`, sorted. Used to enumerate user skill trees.
    func overrideFileNamesRecursive(inRelativeDir relativeDir: String) -> [String] {
        guard let overrideRoot else { return [] }
        return Self.regularFileNamesRecursive(
            in: overrideRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        ).sorted()
    }

    // Excludes the typed category dirs (surfaced through their own walks) and noise,
    // leaving the arbitrary files a user authored or dropped anywhere in the tree.
    // Returned paths are relative to `inRoot`; suppression
    // and the tombstones-metadata skip are checked against the full store path so a
    // scoped scan still honours store-root tombstones. `inRoot: ""` (the default) is the
    // historical store-root scan, byte-identical to before.
    func overrideRootArbitraryFiles(
        inRoot root: String = "", excludingTopLevel excluded: Set<String>
    )
        -> [String]
    {
        guard let overrideRoot else { return [] }
        let scopeDir =
            root.isEmpty
            ? overrideRoot : overrideRoot.appending(path: root, directoryHint: .isDirectory)
        let suppressed = suppressedRelativePaths()
        return Self.regularFileNamesRecursive(in: scopeDir).filter { relative in
            let fullStore = root.isEmpty ? relative : "\(root)/\(relative)"
            if fullStore == Self.tombstonesFileName { return false }  // store metadata, not a project file
            if suppressed.contains(fullStore) { return false }
            let first = relative.split(separator: "/").first.map(String.init) ?? relative
            return !excluded.contains(first)
        }.sorted()
    }

    // Union of regular file sub-paths (relative to `relativeDir`) found recursively
    // in the bundled and override copies of `relativeDir`, sorted and de-duplicated.
    // Used to build the content tree, where a directory's full subtree (e.g. a skill
    // folder with reference files) must show every file, bundled or user-authored.
    func unionFileNamesRecursive(inRelativeDir relativeDir: String) -> [String] {
        var names = Set(Self.regularFileNamesRecursive(in: bundledRoot.appending(path: relativeDir)))
        names.formUnion(overrideFileNamesRecursive(inRelativeDir: relativeDir))
        let suppressed = suppressedRelativePaths()
        return names.filter { !suppressed.contains("\(relativeDir)/\($0)") }.sorted()
    }

    // So the content tree can show user-created folders even when still empty. Noise/VCS
    // dirs (`.git`) are skipped, matching the file walks. `inRoot` scopes the walk to a
    // manager tier's subtree; returned paths are relative to that root. Empty
    // (the default) is the historical store-root walk.
    func overrideDirectoryPaths(inRoot root: String = "") -> [String] {
        guard let overrideRoot else { return [] }
        let scopeDir =
            root.isEmpty
            ? overrideRoot : overrideRoot.appending(path: root, directoryHint: .isDirectory)
        guard
            let enumerator = FileManager.default.enumerator(
                at: scopeDir, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }
        let base = scopeDir.standardizedFileURL.path + "/"
        var result: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            let relative = url.standardizedFileURL.path.replacingOccurrences(of: base, with: "")
            guard !Self.pathHasNoiseComponent(relative) else { continue }
            result.append(relative)
        }
        return result.sorted()
    }

    private static func regularFileNamesRecursive(in dir: URL) -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        let base = dir.standardizedFileURL.path + "/"
        var result: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            let relative = url.standardizedFileURL.path.replacingOccurrences(of: base, with: "")
            guard !Self.pathHasNoiseComponent(relative) else { continue }
            result.append(relative)
        }
        return result
    }

    private static func regularFileNames(in dir: URL) -> [String] {
        // Hidden files are kept (dotfiles like `.editorconfig` are real project files)
        // except the macOS/VCS noise filtered by `isNoise`.
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return
            contents
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.lastPathComponent)
            .filter { !Self.isNoise($0) }
    }

    // MARK: - Scope-composed loose surfaces

    // Variants are ordered earliest/least-specific root first (conflict rule
    // Base < Component < Template) because `resolveLooseFile` relies on that order:
    // earliest is the merge skeleton, latest is the file-level winner.
    func composedLooseFileVariants(category: String, roots: [String]) -> [(name: String, variants: [String])] {
        var variants: [String: [String]] = [:]
        for root in roots {
            let dir = root.isEmpty ? category : "\(root)/\(category)"
            for name in unionFileNames(inRelativeDir: dir) { variants[name, default: []].append("\(dir)/\(name)") }
        }
        return variants.keys.sorted().compactMap { name in variants[name].map { (name, $0) } }
    }

    // How a same-named loose file resolves to final bytes.
    enum ResolvedLooseFile: Equatable {
        case copy(URL)  // file-level override winner, copied verbatim (also: binary files)
        case merged(Data)  // placeholder-merged text

        // `.copy` stays a verbatim file copy so binary files survive unchanged.
        func write(to dest: URL, using fileManager: FileManager = .default) throws {
            switch self {
            case .copy(let source): try fileManager.copyItem(at: source, to: dest)
            case .merged(let data): try data.write(to: dest, options: .atomic)
            }
        }
    }

    // Resolve same-named `variants` (earliest root first) to final content. The earliest
    // variant is the skeleton: if it carries `<<<keyword>>>` placeholders, every variant
    // is harvested for `%% keyword %%` blocks and merged into it; otherwise the latest
    // variant wins verbatim — so a non-placeholder
    // or binary file is unchanged. The placeholder merge is opt-in and additive.
    func resolveLooseFile(variants: [String]) throws -> ResolvedLooseFile {
        guard let skeletonRel = variants.first else { return .merged(Data()) }
        let winnerRel = variants[variants.count - 1]
        guard let skeleton = try? String(contentsOf: url(forRelative: skeletonRel), encoding: .utf8),
            PlaceholderMerge.hasPlaceholders(skeleton)
        else { return .copy(url(forRelative: winnerRel)) }

        // The skeleton (variants[0]) is already read; harvest the remaining variants too.
        let contributions = try [skeleton] + variants.dropFirst().map { try string(atRelative: $0) }
        let merged = try PlaceholderMerge.merge(skeleton: skeleton, contributions: contributions)
        return .merged(Data(merged.utf8))
    }

    // The typed/composition namespaces handled by their own scaffold steps; the
    // arbitrary-file copy skips them so it only reproduces the user's hand-built tree.
    // Mirrors the manager's `typedStoreTopLevel` — `.claude` is intentionally absent so a
    // loose `.claude/<path>` file is reproduced at `<project>/.claude/<path>`.
    static let compositionTopLevel: Set<String> = [
        "hooks", "docs", "skills", "agents", "issues",
        "templates", "components", "template-images", "configs",
    ]

    // The arbitrary-file counterpart of `composedLooseFileVariants` (same earliest-first
    // ordering), for files outside the typed/composition namespaces — the user's hand-built
    // tree, reproduced verbatim at the project root.
    func composedArbitraryFileVariants(roots: [String]) -> [(output: String, variants: [String])] {
        var variants: [String: [String]] = [:]
        for root in roots {
            let excluded: Set<String> = root.isEmpty ? Self.compositionTopLevel : ["docs", "skills", "agents"]
            for rel in overrideRootArbitraryFiles(inRoot: root, excludingTopLevel: excluded) {
                variants[rel, default: []].append(root.isEmpty ? rel : "\(root)/\(rel)")
            }
        }
        return variants.keys.sorted().compactMap { out in variants[out].map { (out, $0) } }
    }

    // The skill directories composed across `roots` plus the bundled workflow skills
    // (which live at the base root only), later roots winning. Each entry pairs the
    // skill name with the store-relative skill dir to copy via `copyResolvedTree`.
    func composedSkillDirs(roots: [String]) -> [(name: String, relativeDir: String)] {
        var winner: [String: String] = [:]
        for name in Self.bundledSkillNames { winner[name] = "skills/\(name)" }
        for root in roots {
            let prefix = root.isEmpty ? "skills" : "\(root)/skills"
            for name in overrideSkillDirNames(inRoot: root) { winner[name] = "\(prefix)/\(name)" }
        }
        return winner.keys.sorted().compactMap { name in winner[name].map { (name, $0) } }
    }

    // User hooks are scope-owned: `hooks/` (Base), `components/<id>/hooks/`,
    // `templates/<id>/hooks/`. A base file whose stem matches a bundled hook is a
    // content override of a built-in, not a user hook. Later roots win a stem clash.
    func scopedUserHookFiles(roots: [String]) -> [(base: String, relativePath: String)] {
        let bundledStems = Set(
            Self.regularFileNames(in: bundledRoot.appending(path: "hooks", directoryHint: .isDirectory))
                .map { ($0 as NSString).deletingPathExtension })
        var pathByBase: [String: String] = [:]
        var order: [String] = []
        for root in roots {
            let dir = root.isEmpty ? "hooks" : "\(root)/hooks"
            for file in overrideFileNames(inRelativeDir: dir) {
                let base = (file as NSString).deletingPathExtension
                if root.isEmpty, bundledStems.contains(base) { continue }
                if pathByBase[base] == nil { order.append(base) }
                pathByBase[base] = "\(dir)/\(file)"
            }
        }
        return order.compactMap { base in pathByBase[base].map { (base, $0) } }
    }

    // One hook name maps to one file and one wiring, so a new hook's stem must be
    // free across every scope hook dir and the bundled built-ins — not just its tier.
    func allScopeHookStems() -> Set<String> {
        var dirs = ["hooks"]
        if let overrideRoot {
            for parent in ["components", "templates"] {
                let parentURL = overrideRoot.appending(path: parent, directoryHint: .isDirectory)
                let subs =
                    (try? FileManager.default.contentsOfDirectory(
                        at: parentURL, includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles])) ?? []
                for sub in subs
                where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    dirs.append("\(parent)/\(sub.lastPathComponent)/hooks")
                }
            }
        }
        var stems = Set(
            Self.regularFileNames(in: bundledRoot.appending(path: "hooks", directoryHint: .isDirectory))
                .map { ($0 as NSString).deletingPathExtension })
        for dir in dirs {
            stems.formUnion(
                overrideFileNames(inRelativeDir: dir).map { ($0 as NSString).deletingPathExtension })
        }
        return stems
    }

    // MARK: - Resolved tree copy (shared by scaffolder + migrator)

    static let bundledSkillNames = ["plumage-plan", "plumage-implement", "plumage-review"]

    // The source tree defines the file set: the bundled dir for a bundled skill (an
    // override replaces a file's content, never adds files), or the override dir for a
    // user-authored skill with no bundled baseline. macOS/VCS noise is never copied out.
    func copyResolvedTree(relativeDir: String, to dest: URL) throws {
        let fileManager = FileManager.default
        let bundledDir = bundledRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        let sourceDir =
            fileManager.fileExists(atPath: bundledDir.path)
            ? bundledDir : (overrideURL(forRelative: relativeDir) ?? bundledDir)
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        guard
            let enumerator = fileManager.enumerator(
                at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey])
        else { return }
        for case let entry as URL in enumerator {
            let isRegular = (try entry.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile ?? false
            guard isRegular else { continue }
            let suffix = entry.standardizedFileURL.path
                .replacingOccurrences(of: sourceDir.standardizedFileURL.path + "/", with: "")
            guard !Self.pathHasNoiseComponent(suffix) else { continue }
            let resolved = url(forRelative: "\(relativeDir)/\(suffix)")
            let target = dest.appending(path: suffix)
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: resolved, to: target)
        }
    }

    static func setExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func makeExecutable(scriptsIn dir: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: dir.path) else { return }
        for entry in try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where entry.pathExtension == "sh" || entry.pathExtension == "py" {
            try setExecutable(entry)
        }
    }

    // MARK: - Noise

    // macOS/VCS metadata that must never reach the tree or scaffold output.
    static func isNoise(_ fileName: String) -> Bool {
        fileName == ".DS_Store" || fileName.hasPrefix("._")
            || fileName == ".git" || fileName == ".svn" || fileName == ".hg"
    }

    // True when any path component is noise — so a file *inside* a `.git/` directory is
    // excluded by its ancestor even though its own leaf name is innocuous.
    static func pathHasNoiseComponent(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { isNoise(String($0)) }
    }
}
