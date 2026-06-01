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

    // The standard resolver: bundled assets overlaid by the user's store at
    // `~/Library/Application Support/Plumage/NewProjectAssets/`. The override root
    // is computed but not created here — it materializes when the editor first
    // writes an override.
    static func standard(
        bundledRoot: URL = NewProjectAssets.bundledRoot
    ) -> ScaffoldOverrides {
        let override = try? ApplicationSupport.appFolderURL()
            .appending(path: NewProjectAssets.folderName, directoryHint: .isDirectory)
        return ScaffoldOverrides(bundledRoot: bundledRoot, overrideRoot: override)
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
}
