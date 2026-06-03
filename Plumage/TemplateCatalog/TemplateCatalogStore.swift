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
        guard let url = manifestURL, FileManager.default.fileExists(atPath: url.path) else {
            return .bundledDefault
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(TemplateManifest.self, from: data)
            return TemplateCatalog(manifest: manifest)
        } catch {
            Self.logger.warning(
                "Template manifest unreadable at \(url.path, privacy: .public); using bundled default: \(error.localizedDescription, privacy: .public)"
            )
            return .bundledDefault
        }
    }

    // Persists `catalog` as its minimal overlay manifest. The write is atomic
    // (temp file + rename, via `Data`'s `.atomic` option) so a crash mid-write
    // can never leave a half-written manifest. A single writer (the manager
    // window), so no cross-process locking is needed.
    func save(_ catalog: TemplateCatalog) throws {
        guard let url = manifestURL else { throw TemplateCatalogStoreError.noManifestURL }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog.manifest)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
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
