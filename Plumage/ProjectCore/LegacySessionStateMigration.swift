import Foundation

// Without this, upgraders' chat sessions silently start fresh: chat-id used
// to live at `<root>/.plumage/sessions/chat-id`, state now lives in the
// bundle. terminal-id is intentionally not migrated — already ephemeral.
nonisolated enum LegacySessionStateMigration {
    static func migrate(root: URL, bundle: URL) {
        // Resolution can fall back to the root itself; nothing to migrate then.
        guard root.standardizedFileURL != bundle.standardizedFileURL else { return }

        let fm = FileManager.default
        let legacy =
            root
            .appendingPathComponent(".plumage", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("chat-id")
        guard fm.fileExists(atPath: legacy.path) else { return }

        let destDir = bundle.appendingPathComponent("sessions", isDirectory: true)
        let dest = destDir.appendingPathComponent("chat-id")
        // Never clobber an already-migrated pointer.
        guard !fm.fileExists(atPath: dest.path) else { return }

        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        try? fm.moveItem(at: legacy, to: dest)
    }
}
