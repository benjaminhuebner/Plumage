import Foundation
import Testing

@testable import Plumage

@Suite("SpecWriter")
struct SpecWriterTests {
    @Test("writes new file with content")
    func writesNewFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("spec.md")

        try SpecWriter.write("hello world", to: url)

        let read = try String(contentsOf: url, encoding: .utf8)
        #expect(read == "hello world")
    }

    @Test("overwrites existing file")
    func overwritesExisting() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("spec.md")
        try "original".write(to: url, atomically: true, encoding: .utf8)

        try SpecWriter.write("replaced", to: url)

        let read = try String(contentsOf: url, encoding: .utf8)
        #expect(read == "replaced")
    }

    @Test("writes empty content as zero-byte file")
    func writesEmptyContent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("spec.md")

        try SpecWriter.write("", to: url)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.size] as? Int) == 0)
    }

    @Test("write to non-existent directory throws")
    func throwsOnMissingDirectory() {
        let bogus = URL(filePath: "/nonexistent-dir-\(UUID().uuidString)/spec.md")
        #expect(throws: (any Error).self) {
            try SpecWriter.write("x", to: bogus)
        }
    }

    @Test("atomic write leaves no sibling tempfile behind")
    func atomicWriteCleansUp() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("spec.md")

        try SpecWriter.write("payload", to: url)

        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(siblings == ["spec.md"])
    }

    private func makeTempDir() throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("SpecWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
