import Foundation

nonisolated enum TemplateArchiveZipError: LocalizedError, Equatable {
    case packFailed(String)
    case corruptArchive(String)
    case entryEscapesDestination(String)
    case symlinkEntry(String)

    var errorDescription: String? {
        switch self {
        case .packFailed(let detail):
            return "Couldn't create the archive: \(detail.prefix(200))"
        case .corruptArchive(let detail):
            return "Not a readable template archive: \(detail.prefix(200))"
        case .entryEscapesDestination(let name):
            return "Archive rejected: entry \"\(name)\" escapes the extraction folder."
        case .symlinkEntry(let path):
            return "Archive rejected: it contains a symbolic link (\(path))."
        }
    }
}

// Pack/unpack via /usr/bin/ditto — no archive-library dependency; same
// subprocess pattern as GitProcessRunning. Unpack pre-validates the entry
// listing (zipinfo) so a traversal entry is rejected before disk is touched.
nonisolated struct TemplateArchiveZip: Sendable {
    private static let dittoURL = URL(filePath: "/usr/bin/ditto")
    private static let zipinfoURL = URL(filePath: "/usr/bin/zipinfo")

    private let runner: any TemplateArchiveProcessRunning

    init(runner: any TemplateArchiveProcessRunning = ProductionTemplateArchiveProcessRunner()) {
        self.runner = runner
    }

    func pack(directory: URL, to archiveURL: URL) async throws {
        // --norsrc: without it ditto stores xattrs as AppleDouble (._*) zip
        // entries — quarantine flags and Finder metadata don't belong in exports.
        let result = try await runner.run(
            binaryURL: Self.dittoURL,
            args: ["-c", "-k", "--norsrc", directory.path, archiveURL.path],
            cwd: nil
        )
        guard result.exitCode == 0 else {
            throw TemplateArchiveZipError.packFailed(
                String(decoding: result.stderr, as: UTF8.self))
        }
    }

    func unpack(archive: URL, to destination: URL) async throws {
        let listing = try await runner.run(
            binaryURL: Self.zipinfoURL,
            args: ["-1", archive.path],
            cwd: nil
        )
        guard listing.exitCode == 0 else {
            throw TemplateArchiveZipError.corruptArchive(
                String(decoding: listing.stderr, as: UTF8.self))
        }
        let names = String(decoding: listing.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init)
        try Self.validateEntryNames(names)

        let result = try await runner.run(
            binaryURL: Self.dittoURL,
            args: ["-x", "-k", "--norsrc", archive.path, destination.path],
            cwd: nil
        )
        guard result.exitCode == 0 else {
            throw TemplateArchiveZipError.corruptArchive(
                String(decoding: result.stderr, as: UTF8.self))
        }
        try Self.rejectSymlinks(under: destination)
    }

    // Rejects absolute entries and any `..` path component — a hostile archive
    // must not be able to write outside the staging directory. Backslash counts
    // as a separator too: Windows-built zips may use it for traversal.
    static func validateEntryNames(_ names: [String]) throws {
        for name in names {
            guard !name.hasPrefix("/"), !name.hasPrefix("\\") else {
                throw TemplateArchiveZipError.entryEscapesDestination(name)
            }
            if name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") {
                throw TemplateArchiveZipError.entryEscapesDestination(name)
            }
        }
    }

    // Our exports never contain symlinks; an archive that does is hostile or
    // foreign (zip-slip writes through an extracted link), so reject outright.
    static func rejectSymlinks(under root: URL) throws {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        )
        while let item = enumerator?.nextObject() as? URL {
            let isLink =
                (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
            if isLink {
                throw TemplateArchiveZipError.symlinkEntry(item.lastPathComponent)
            }
        }
    }
}
