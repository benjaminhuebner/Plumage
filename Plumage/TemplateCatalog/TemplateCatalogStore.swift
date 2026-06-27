import Foundation
import os

// Resolves the template catalog: a decodable manifest in Application Support
// overrides the bundled default; a missing manifest yields the bundled default;
// an unreadable or partial manifest falls back to the bundled default with a
// logged warning (never crashes). The manifest lives next to the other Plumage
// app-support files, never the Claude config directory (CCI boundary intact).
nonisolated struct TemplateCatalogStore: Sendable {
    let manifestURL: URL?

    init(manifestURL: URL? = TemplateCatalogStore.standardManifestURL()) {
        self.manifestURL = manifestURL
    }

    private static let logger = Logger(subsystem: "com.plumage", category: "TemplateCatalogStore")
    static let fileName = "template-manifest.json"

    static func standardManifestURL() -> URL? {
        try? ApplicationSupport.appFolderURL().appending(path: fileName)
    }

    func load() -> TemplateCatalog {
        loadDiagnosed().catalog
    }

    // Like `load()` but reports whether a present manifest failed to decode, so a UI
    // surface can warn the user instead of silently falling back to the bundled default.
    func loadDiagnosed() -> (catalog: TemplateCatalog, corrupt: Bool) {
        guard let url = manifestURL, FileManager.default.fileExists(atPath: url.path) else {
            return (.bundledDefault, false)
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(TemplateManifest.self, from: data)
            return (TemplateCatalog(manifest: manifest), false)
        } catch {
            Self.logger.warning(
                "Template manifest unreadable at \(url.path, privacy: .public); using bundled default: \(error.localizedDescription, privacy: .public)"
            )
            return (.bundledDefault, true)
        }
    }

    // Persists `catalog` as its minimal overlay manifest. The write is atomic
    // (temp file + rename, via `Data`'s `.atomic` option) so a crash mid-write
    // can never leave a half-written manifest. A single writer (the manager
    // window), so no cross-process locking is needed.
    func save(_ catalog: TemplateCatalog) throws {
        guard let url = manifestURL else { throw TemplateCatalogStoreError.noManifestURL }
        // An unreadable manifest must never be overwritten in place — set it aside first
        // so the user's structure stays recoverable instead of being lost to the overlay.
        try setAsideCorruptManifest(at: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog.manifest)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // Moves a present-but-undecodable manifest to a timestamped sidecar. No-op when the
    // manifest is absent or decodes fine, so normal saves are untouched.
    @discardableResult
    func setAsideCorruptManifest(at url: URL) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            (try? JSONDecoder().decode(TemplateManifest.self, from: data)) == nil
        else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        let sidecar = url.deletingLastPathComponent()
            .appending(path: "\(base).corrupt-\(Self.corruptStamp()).\(ext)")
        try fm.moveItem(at: url, to: sidecar)
        Self.logger.warning(
            "Set aside unreadable manifest to \(sidecar.lastPathComponent, privacy: .public)")
        return sidecar
    }

    private static func corruptStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    // Drops the persisted overlay entirely, returning the catalog to the bundled
    // baseline on the next `load()`. File-content overrides (a separate store) are
    // untouched. No-op when the manifest does not exist.
    func reset() throws {
        guard let url = manifestURL else { throw TemplateCatalogStoreError.noManifestURL }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

nonisolated enum TemplateCatalogStoreError: Error, LocalizedError {
    case noManifestURL

    var errorDescription: String? {
        switch self {
        case .noManifestURL: "No template manifest location is available to write to."
        }
    }
}
