import Foundation

// Installs Plumage's bundled `plumage` claude theme into ~/.claude/ so the
// embedded terminal renders without opaque block backgrounds, regardless of
// macOS appearance. The bundled JSON is the single source of truth; we
// overwrite on each Plumage boot so a Plumage update can ship a refreshed
// theme. Settings.json is updated more carefully — only flip `theme` to
// `plumage` if the user hasn't explicitly chosen a different non-plumage
// theme since the last install (i.e., if the field is missing OR already
// set to `plumage`).
// Pure file-I/O type with no UI state. Nonisolated so it can run from any
// context (NSApplicationDelegate callback, tests, etc.) without forcing a
// hop to MainActor — the default-actor-isolation project setting would
// otherwise pin it to MainActor.
nonisolated enum ClaudeThemeInstaller {
    enum InstallError: Error {
        case bundleResourceMissing
        case homeDirectoryUnavailable
    }

    static let themeName = "plumage"
    static let bundledResource = "plumage-theme"
    static let bundledExtension = "json"

    static func installIfNeeded(bundle: Bundle = .main, fileManager: FileManager = .default) {
        do {
            guard
                let sourceURL = bundle.url(
                    forResource: bundledResource, withExtension: bundledExtension)
            else { throw InstallError.bundleResourceMissing }
            try writeThemeFile(sourceURL: sourceURL, fileManager: fileManager)
            try ensureSettingsTheme(fileManager: fileManager)
        } catch {
            // Theme install is best-effort. A failure here must not block
            // Plumage's startup — the embedded terminal still works with
            // whatever theme claude picks up.
        }
    }

    static func writeThemeFile(
        sourceURL: URL,
        fileManager: FileManager = .default,
        destination: URL? = nil
    ) throws {
        let data = try Data(contentsOf: sourceURL)
        let target = try destination ?? defaultThemeFileURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    static func ensureSettingsTheme(
        fileManager: FileManager = .default,
        settingsURL: URL? = nil
    ) throws {
        let url = try settingsURL ?? defaultSettingsFileURL(fileManager: fileManager)
        var json: [String: Any]
        if fileManager.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            json = parsed
        } else {
            json = [:]
        }
        // Only set theme if absent or already plumage. Respect a user's manual
        // override to a different theme — they may prefer it.
        let current = json["theme"] as? String
        if current == nil || current == themeName {
            json["theme"] = themeName
            let updated = try JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: url, options: .atomic)
        }
    }

    static func defaultThemeFileURL(fileManager: FileManager) throws -> URL {
        try claudeHomeDirectory(fileManager: fileManager)
            .appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("\(themeName).json")
    }

    static func defaultSettingsFileURL(fileManager: FileManager) throws -> URL {
        try claudeHomeDirectory(fileManager: fileManager)
            .appendingPathComponent("settings.json")
    }

    private static func claudeHomeDirectory(fileManager: FileManager) throws -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        guard !home.path.isEmpty else { throw InstallError.homeDirectoryUnavailable }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }
}
