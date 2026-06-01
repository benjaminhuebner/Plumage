import Foundation

// Per-file override layer over the bundled `NewProjectAssets/` tree. Each relative
// path resolves to the user's override copy under Application Support when present,
// else the bundled original — so a user can override `templates/macos.md` without
// touching `templates/swift-shared.md` (a per-directory layer would force
// all-or-nothing). The override root mirrors the bundled tree flat. The store lives
// under Application Support, never the user's Claude config directory, so the
// ClaudeCodeIntegration boundary is untouched.
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

    // File names directly inside the override `<relativeDir>` directory, sorted.
    // Used for catalogs that have no bundled baseline (user-authored agents):
    // the set of files is whatever the user created. Empty when there is no
    // override store or the directory is absent.
    func overrideFileNames(inRelativeDir relativeDir: String) -> [String] {
        guard let overrideRoot else { return [] }
        let dir = overrideRoot.appending(path: relativeDir, directoryHint: .isDirectory)
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.lastPathComponent)
            .sorted()
    }
}
