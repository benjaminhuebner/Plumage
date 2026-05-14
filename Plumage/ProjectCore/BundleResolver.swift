import Foundation

nonisolated enum BundleResolver {
    static let bundleExtension = "plumage"

    enum ResolveError: Error, Equatable, Sendable {
        case noBundle(folder: URL)
        case multipleBundles(found: [URL])
    }

    static func resolve(from url: URL) throws -> (root: URL, bundle: URL) {
        let standardized = url.standardizedFileURL
        if standardized.pathExtension == bundleExtension {
            let root = standardized.deletingLastPathComponent()
            return (root: root, bundle: standardized)
        }
        let bundle = try findBundle(in: standardized)
        return (root: standardized, bundle: bundle)
    }

    static func findBundle(in projectRoot: URL) throws -> URL {
        let fm = FileManager.default
        let entries =
            (try? fm.contentsOfDirectory(
                at: projectRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )) ?? []

        let bundles = entries.filter { $0.pathExtension == bundleExtension }

        if bundles.count > 1 {
            throw ResolveError.multipleBundles(found: bundles.sorted { $0.path < $1.path })
        }
        if let only = bundles.first {
            return only
        }
        throw ResolveError.noBundle(folder: projectRoot)
    }
}
