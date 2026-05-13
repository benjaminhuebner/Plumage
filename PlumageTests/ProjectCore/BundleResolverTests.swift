import Foundation
import Testing

@testable import Plumage

struct BundleResolverTests {
    private func makeTempRoot() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func mkdir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @Test func findBundleReturnsPlumageBundle() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("MyProject.plumage", isDirectory: true)
        try mkdir(bundle)

        let found = try BundleResolver.findBundle(in: root)
        #expect(found.standardizedFileURL == bundle.standardizedFileURL)
    }

    @Test func findBundleIgnoresLegacyDotfile() throws {
        // Foundation's URL/NSString treats leading-dot filenames as having no
        // extension, so `.plumage` has pathExtension "" — the legacy dotfile
        // cannot match the bundle filter even by accident.
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let dotfile = root.appendingPathComponent(".plumage", isDirectory: true)
        try mkdir(dotfile)

        #expect {
            try BundleResolver.findBundle(in: root)
        } throws: { error in
            guard case BundleResolver.ResolveError.noBundle = error else { return false }
            return true
        }
    }

    @Test func findBundleThrowsWhenNothingMatches() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect {
            try BundleResolver.findBundle(in: root)
        } throws: { error in
            guard case BundleResolver.ResolveError.noBundle(let folder) = error else { return false }
            return folder.standardizedFileURL == root.standardizedFileURL
        }
    }

    @Test func multipleBundlesThrows() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let alpha = root.appendingPathComponent("Alpha.plumage", isDirectory: true)
        let beta = root.appendingPathComponent("Beta.plumage", isDirectory: true)
        try mkdir(alpha)
        try mkdir(beta)

        #expect {
            try BundleResolver.findBundle(in: root)
        } throws: { error in
            guard case BundleResolver.ResolveError.multipleBundles(let urls) = error else {
                return false
            }
            let names = urls.map { $0.lastPathComponent }.sorted()
            return names == ["Alpha.plumage", "Beta.plumage"]
        }
    }

    @Test func resolveFromBundleURLDerivesRoot() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("MyProject.plumage", isDirectory: true)
        try mkdir(bundle)

        let result = try BundleResolver.resolve(from: bundle)
        #expect(result.root.standardizedFileURL == root.standardizedFileURL)
        #expect(result.bundle.standardizedFileURL == bundle.standardizedFileURL)
    }

    @Test func resolveFromFolderURLFindsBundle() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("MyProject.plumage", isDirectory: true)
        try mkdir(bundle)

        let result = try BundleResolver.resolve(from: root)
        #expect(result.root.standardizedFileURL == root.standardizedFileURL)
        #expect(result.bundle.standardizedFileURL == bundle.standardizedFileURL)
    }
}
