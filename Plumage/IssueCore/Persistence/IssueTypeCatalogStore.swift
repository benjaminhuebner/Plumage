import Foundation
import os

// The same file is read by the plumage-implement start-run gate, so app and
// shell agree on which types block Implement from draft. Missing/unreadable
// file yields the built-in catalog (never crashes).
nonisolated struct IssueTypeCatalogStore: Sendable {
    let fileURL: URL?

    init(fileURL: URL? = IssueTypeCatalogStore.standardFileURL()) {
        self.fileURL = fileURL
    }

    private static let logger = Logger(subsystem: "com.plumage", category: "IssueTypeCatalogStore")
    static let fileName = "issue-types.json"

    static func standardFileURL() -> URL? {
        try? ApplicationSupport.appFolderURL().appending(path: fileName)
    }

    func load() -> IssueTypeCatalog {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            return .builtIn
        }
        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(IssueTypeCatalog.self, from: data)
            guard !catalog.definitions.isEmpty else { return .builtIn }
            return catalog
        } catch {
            Self.logger.warning(
                "Issue-type catalog unreadable at \(url.path, privacy: .public); using built-in default: \(error.localizedDescription, privacy: .public)"
            )
            return .builtIn
        }
    }

    func save(_ catalog: IssueTypeCatalog) throws {
        guard let url = fileURL else { throw IssueTypeCatalogStoreError.noFileURL }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

nonisolated enum IssueTypeCatalogStoreError: Error, LocalizedError {
    case noFileURL

    var errorDescription: String? {
        switch self {
        case .noFileURL: "No issue-type catalog location is available to write to."
        }
    }
}
