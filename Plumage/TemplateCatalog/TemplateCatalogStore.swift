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
}
