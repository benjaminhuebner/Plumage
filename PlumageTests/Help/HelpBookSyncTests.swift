import Foundation
import Testing

@testable import Plumage

@Suite("Help book sync")
struct HelpBookSyncTests {
    private static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("every topic source matches the generated in-app content")
    func topicsMatchSources() throws {
        let topicsDir = Self.repoRoot.appending(path: "HelpBook/topics")
        let sources = try FileManager.default
            .contentsOfDirectory(at: topicsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        #expect(sources.count == HelpTopic.all.count)
        for source in sources {
            let text = try String(contentsOf: source, encoding: .utf8)
            let parts = text.components(separatedBy: "---\n")
            try #require(parts.count >= 3, "\(source.lastPathComponent): missing frontmatter")
            let id = try #require(
                frontmatterValue(parts[1], key: "id"),
                "\(source.lastPathComponent): missing id"
            )
            let topic = try #require(
                HelpTopic.all.first { $0.id == id },
                "no HelpTopic for source \(id) — run HelpBook/generate.py"
            )
            let body = parts.dropFirst(2).joined(separator: "---\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(topic.markdown == body, "\(id) drifted — run HelpBook/generate.py")
        }
    }

    @Test("the help book ships one page per topic plus index and search index")
    func helpBookIsComplete() {
        let lproj = Self.repoRoot.appending(
            path: "Plumage/HelpBook/Plumage.help/Contents/Resources/en.lproj")
        var expected = HelpTopic.all.map { "\($0.id).html" }
        expected += ["index.html", "style.css", "Plumage.helpindex"]
        for name in expected {
            let present = FileManager.default.fileExists(
                atPath: lproj.appending(path: name).path)
            #expect(present, "\(name) missing — run HelpBook/generate.py")
        }
    }

    private func frontmatterValue(_ frontmatter: String, key: String) -> String? {
        for line in frontmatter.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces) == key {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
