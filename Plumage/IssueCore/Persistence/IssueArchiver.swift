import Foundation

nonisolated enum IssueArchiver {
    // Cap exists so an adversarial filesystem state fails deterministically
    // instead of spinning. Unreachable under normal single-writer access.
    static let maxArchiveSuffix = 1000

    static func archive(folderURL: URL, archiveRoot: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        // Attempt-then-handle instead of exists-then-move: a pre-scan races
        // a concurrent writer claiming the same destination (TOCTOU).
        let base = folderURL.lastPathComponent
        for suffix in 0...maxArchiveSuffix {
            let name = suffix == 0 ? base : "\(base)-\(suffix)"
            let destination = archiveRoot.appendingPathComponent(name, isDirectory: true)
            do {
                try fileManager.moveItem(at: folderURL, to: destination)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    static func trash(folderURL: URL) throws -> URL {
        // FileManager.trashItem uses an autoreleasing out-parameter for the
        // resulting URL. Bridge: declare an NSURL? optional and pass via &.
        // The function still throws on failure (unsupported volume,
        // permissions); we propagate that to the caller.
        var resulting: NSURL?
        try FileManager.default.trashItem(at: folderURL, resultingItemURL: &resulting)
        guard let resulting = resulting as URL? else {
            // Defensive: trashItem is documented to populate on success.
            throw CocoaError(.fileWriteUnknown)
        }
        return resulting
    }
}
