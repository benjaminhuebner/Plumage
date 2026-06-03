import Foundation

// Per-file override layer over the bundled `NewProjectAssets/` tree. Each relative
// path resolves to the user's override copy under Application Support when present,
// else the bundled original — so a user can override `templates/macos.md` without
// touching `templates/swift-shared.md` (a per-directory layer would force
// all-or-nothing). The override root mirrors the bundled tree flat. The store lives
// under Application Support, never the user's Claude config directory, so the
// ClaudeCodeIntegration boundary is untouched.
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
        return names.sorted()
    }

    // Top-level directory names under the override `skills/` that contain a
    // `SKILL.md` — i.e. user-authored skills (and any bundled skill the user has
    // overridden). Empty with no override store.
    func overrideSkillDirNames() -> [String] {
        guard let overrideRoot else { return [] }
        let skillsDir = overrideRoot.appending(path: "skills", directoryHint: .isDirectory)
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
        let dir = overrideRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        guard
            let enumerator = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        let base = dir.standardizedFileURL.path + "/"
        var result: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            result.append(url.standardizedFileURL.path.replacingOccurrences(of: base, with: ""))
        }
        return result.sorted()
    }

    private static func regularFileNames(in dir: URL) -> [String] {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.lastPathComponent)
    }
}
