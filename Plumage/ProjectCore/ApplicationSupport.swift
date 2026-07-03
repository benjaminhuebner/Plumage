import Foundation

nonisolated enum ApplicationSupport {
    static let appFolderName = "Plumage"
    static let recentFileName = "recent.json"
    static let githubAccountsFileName = "github-accounts.json"

    static func appFolderURL(using fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var app = base.appendingPathComponent(appFolderName, isDirectory: true)
        let created = !fileManager.fileExists(atPath: app.path)
        try fileManager.createDirectory(at: app, withIntermediateDirectories: true)
        if created {
            // Contents are machine-specific caches (absolute paths in recent.json)
            // that are meaningless after a restore on another machine — keep them
            // out of Time Machine / iCloud backups. Only set on first create to
            // avoid touching the flag (and its mtime) on every launch.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? app.setResourceValues(values)
        }
        return app
    }

    static func recentFileURL(using fileManager: FileManager = .default) throws -> URL {
        try appFolderURL(using: fileManager).appendingPathComponent(recentFileName)
    }

    static func githubAccountsFileURL(using fileManager: FileManager = .default) throws -> URL {
        try appFolderURL(using: fileManager).appendingPathComponent(githubAccountsFileName)
    }
}
