import Foundation

nonisolated enum SpecWriterError: Error, Equatable, Sendable {
    case parentDirectoryMissing(URL)
}

nonisolated struct SpecWriter: Sendable {
    static func write(_ content: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            throw SpecWriterError.parentDirectoryMissing(parent)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
