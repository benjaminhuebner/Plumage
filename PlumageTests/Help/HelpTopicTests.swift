import Foundation
import Testing

@testable import Plumage

@Suite("HelpTopic")
struct HelpTopicTests {
    @Test("topic ids are unique")
    func uniqueIDs() {
        let ids = HelpTopic.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("every section has a title and at least one topic")
    func sectionsAreNonEmpty() {
        #expect(!HelpTopic.sections.isEmpty)
        for section in HelpTopic.sections {
            #expect(!section.title.isEmpty)
            #expect(!section.topics.isEmpty)
        }
    }

    @Test("search matches title and body text case-insensitively")
    func searchMatching() {
        let topic = HelpTopic.templateMergeSyntax
        #expect(topic.matches("MERGE"))
        #expect(topic.matches("placeholder"))
        #expect(!topic.matches("definitely-not-in-any-topic"))
    }

    @Test("every topic opens with a level-1 heading")
    func opensWithHeading() {
        for topic in HelpTopic.all {
            #expect(topic.markdown.hasPrefix("# "), "\(topic.id) must start with a `# ` heading")
        }
    }

    @Test("every topic parses into renderable blocks")
    func parsesIntoBlocks() {
        for topic in HelpTopic.all {
            let blocks = MarkdownBlockParser.parse(topic.markdown)
            let hasHeading = blocks.contains {
                if case .heading = $0 { return true }
                return false
            }
            #expect(!blocks.isEmpty, "\(topic.id) produced no blocks")
            #expect(hasHeading, "\(topic.id) produced no heading block")
        }
    }

    @Test("code fences are balanced")
    func balancedFences() {
        for topic in HelpTopic.all {
            let fenceCount = topic.markdown
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count { $0.hasPrefix("```") }
            #expect(fenceCount.isMultiple(of: 2), "\(topic.id) has an unclosed code fence")
        }
    }
}
