import Foundation

nonisolated enum IssueArchiver {
    static func archive(folderURL: URL, archiveRoot: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let destination = nextAvailableDestination(
            base: folderURL.lastPathComponent, archiveRoot: archiveRoot, fileManager: fileManager)
        try fileManager.moveItem(at: folderURL, to: destination)
        return destination
    }

    static func trash(folderURL: URL) throws -> URL {
        // FileManager.trashItem uses an autoreleasing out-parameter for the
        // resulting URL. Bridge: declare an NSURL? optional and pass via &.
        // The function still throws on failure (unsupported volume,
        // permissions); we propagate that to the caller.
        var resulting: NSURL?
        try FileManager.default.trashItem(at: folderURL, resultingItemURL: &resulting)
        guard let resulting = resulting as URL? else {
            throw CocoaError(.fileWriteUnknown)
        }
        return resulting
    }

    private static func nextAvailableDestination(
        base: String, archiveRoot: URL, fileManager: FileManager
    ) -> URL {
        let candidate = archiveRoot.appendingPathComponent(base, isDirectory: true)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        var suffix = 1
        while true {
            let suffixed = archiveRoot.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
            if !fileManager.fileExists(atPath: suffixed.path) {
                return suffixed
            }
            suffix += 1
        }
    }
}
