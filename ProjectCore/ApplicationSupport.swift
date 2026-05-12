import Foundation

nonisolated enum ApplicationSupport {
    static let appFolderName = "Plumage"
    static let recentFileName = "recent.json"

    static func appFolderURL(using fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let app = base.appendingPathComponent(appFolderName, isDirectory: true)
        try fileManager.createDirectory(at: app, withIntermediateDirectories: true)
        return app
    }

    static func recentFileURL(using fileManager: FileManager = .default) throws -> URL {
        try appFolderURL(using: fileManager).appendingPathComponent(recentFileName)
    }
}
