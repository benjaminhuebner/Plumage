import AppKit
import UniformTypeIdentifiers

// Avoids a synchronous Launch Services round-trip per tree row on every
// reload. Keyed by type (directory flag + extension) and resolved via UTType,
// not the path — Template Manager nodes carry synthetic paths off-disk.
@MainActor
enum WorkspaceIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forPath path: String, isDirectory: Bool) -> NSImage {
        let ext = (path as NSString).pathExtension.lowercased()
        let key = (isDirectory ? "d:" : "f:") + ext
        if let cached = cache[key] { return cached }
        let icon: NSImage
        if isDirectory {
            icon = NSWorkspace.shared.icon(for: .folder)
        } else {
            icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        }
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
