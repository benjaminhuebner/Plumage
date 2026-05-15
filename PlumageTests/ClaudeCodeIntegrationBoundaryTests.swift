import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeCodeIntegration boundary")
struct ClaudeCodeIntegrationBoundaryTests {
    @Test("no forbidden patterns outside ClaudeCodeIntegration/")
    func boundaryGrep() throws {
        let plumageRoot = Self.plumageSourceRoot()
        let cciRoot = plumageRoot.appending(path: "ClaudeCodeIntegration", directoryHint: .isDirectory)
        let violations = try BoundaryScanner.scan(
            root: plumageRoot,
            skipping: cciRoot,
            forbidden: BoundaryScanner.forbiddenPatterns
        )
        #expect(violations.isEmpty, "CCI boundary violation(s): \(violations)")
    }

    @Test("scanner reports a violation in a synthetic file")
    func scannerReportsSynthetic() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "PlumageBoundaryProbe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let badFile = tmpDir.appending(path: "BadFile.swift")
        // Use a string that matches exactly one forbidden pattern so the count assertion stays stable.
        try "let bad = \"~/.claude/local/claude\"\n".write(
            to: badFile, atomically: true, encoding: .utf8)

        let cciRoot = tmpDir.appending(path: "ClaudeCodeIntegration", directoryHint: .isDirectory)
        let violations = try BoundaryScanner.scan(
            root: tmpDir,
            skipping: cciRoot,
            forbidden: BoundaryScanner.forbiddenPatterns
        )
        #expect(violations.count == 1)
        #expect(violations.first?.contains("BadFile.swift") == true)
        #expect(violations.first?.contains("~/.claude/") == true)
    }

    @Test("scanner ignores files in the skipped subtree")
    func scannerIgnoresSkipped() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "PlumageBoundaryProbe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let cciRoot = tmpDir.appending(path: "ClaudeCodeIntegration", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cciRoot, withIntermediateDirectories: true)
        let allowedFile = cciRoot.appending(path: "Allowed.swift")
        try "let path = \"~/.claude/local/claude\"\n".write(
            to: allowedFile, atomically: true, encoding: .utf8)

        let violations = try BoundaryScanner.scan(
            root: tmpDir,
            skipping: cciRoot,
            forbidden: BoundaryScanner.forbiddenPatterns
        )
        #expect(violations.isEmpty)
    }

    private static func plumageSourceRoot() -> URL {
        // #filePath = …/PlumageTests/ClaudeCodeIntegrationBoundaryTests.swift
        // Walk up to the repo root, then into Plumage/.
        URL(filePath: #filePath)
            .deletingLastPathComponent()  // PlumageTests/
            .deletingLastPathComponent()  // repo root
            .appending(path: "Plumage", directoryHint: .isDirectory)
    }
}

enum BoundaryScanner {
    static let forbiddenPatterns: [String] = ["~/.claude/", "claude --", ".claude/projects"]

    struct ScanError: Error { let message: String }

    static func scan(root: URL, skipping: URL, forbidden: [String]) throws -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw ScanError(message: "Could not enumerate \(root.path)")
        }

        let skipPrefix = skipping.standardizedFileURL.path
        var violations: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let standardized = url.standardizedFileURL.path
            if standardized == skipPrefix || standardized.hasPrefix(skipPrefix + "/") {
                continue
            }
            let content = try String(contentsOf: url, encoding: .utf8)
            for pattern in forbidden where content.contains(pattern) {
                violations.append("\(url.lastPathComponent): \(pattern)")
            }
        }

        return violations
    }
}
