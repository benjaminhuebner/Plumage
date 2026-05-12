import Foundation
import Testing

@testable import Plumage

struct SchemaVersionTests {
    @Test func currentIsAtLeastOne() {
        #expect(SchemaVersion.current >= 1)
    }

    @Test func equalVersionIsAccepted() throws {
        let folder = try TempProject.make(
            content: """
                { "name": "Equal", "schemaVersion": \(SchemaVersion.current) }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        let config = try ConfigLoader.load(at: folder)
        #expect(config.schemaVersion == SchemaVersion.current)
    }

    @Test func higherVersionIsRejected() throws {
        let folder = try TempProject.make(
            content: """
                { "name": "Too New", "schemaVersion": \(SchemaVersion.current + 1) }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(throws: ConfigLoader.LoadError.self) {
            try ConfigLoader.load(at: folder)
        }
    }
}
