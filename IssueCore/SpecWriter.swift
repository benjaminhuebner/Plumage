import Foundation

nonisolated struct SpecWriter: Sendable {
    static func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
