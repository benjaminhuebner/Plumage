import AppKit

// Avoids a synchronous Launch Services round-trip per sidebar row on every
// reload. Keyed by type (directory flag + extension) rather than full path
// because `icon(forFile:)` resolves by UTI — files of one extension, and plain
// folders, share an icon. MainActor-confined, so the dictionary needs no lock.
@MainActor
enum WorkspaceIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forPath path: String, isDirectory: Bool) -> NSImage {
        let ext = (path as NSString).pathExtension.lowercased()
        let key = (isDirectory ? "d:" : "f:") + ext
        if let cached = cache[key] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[key] = icon
        return icon
    }

    // For callers that don't already know file-vs-folder (e.g. the pinned
    // section, which is a handful of rows). Resolves the directory flag once.
    static func icon(forPath path: String) -> NSImage {
        let isDir =
            (try? URL(filePath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return icon(forPath: path, isDirectory: isDir)
    }
}
