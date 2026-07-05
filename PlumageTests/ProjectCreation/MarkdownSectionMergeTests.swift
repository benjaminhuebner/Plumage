import Foundation
import Testing

@testable import Plumage

@Suite("MarkdownSectionMerge")
struct MarkdownSectionMergeTests {
    @Test("A repeated heading fuses the contribution's items into the base list")
    func sameHeadingFusesLists() {
        let base = "# Doc\n\n## Refs\n- one\n- two\n\n## Keep\nprose\n"
        let contribution = "## Refs\n- three\n"
        let merged = MarkdownSectionMerge.merge(variants: [base, contribution])
        #expect(merged == "# Doc\n\n## Refs\n- one\n- two\n- three\n\n## Keep\nprose\n")
    }

    @Test("An unknown heading appends as a new section at the end")
    func newHeadingAppends() {
        let base = "## A\n- a\n"
        let contribution = "## B\n- b\n"
        let merged = MarkdownSectionMerge.merge(variants: [base, contribution])
        #expect(merged == "## A\n- a\n\n## B\n- b\n")
    }

    @Test("Later variants keep merging in order")
    func multipleVariantsInOrder() {
        let merged = MarkdownSectionMerge.merge(variants: [
            "## S\n\n## T\n- t\n", "## S\n- first\n", "## S\n- second\n",
        ])
        #expect(merged == "## S\n- first\n- second\n\n## T\n- t\n")
    }

    @Test("Lines the base section already has are not duplicated")
    func dedupWithinSection() {
        let base = "## S\n- a\n- b\n"
        let contribution = "## S\n- b\n- c\n"
        let merged = MarkdownSectionMerge.merge(variants: [base, contribution])
        #expect(merged == "## S\n- a\n- b\n- c\n")
    }

    @Test("Merging an identical copy is a no-op")
    func identicalCopyNoOp() {
        let doc = "# Title\n\n## S\n- a\n\n## T\n- b\n"
        #expect(MarkdownSectionMerge.merge(variants: [doc, doc]) == doc)
    }

    @Test("Content past the contribution's first blank line lands at the section end")
    func tailContentAppends() {
        let base = "## S\n- a\n\nBase paragraph.\n"
        let contribution = "## S\n- b\n\nContribution paragraph.\n"
        let merged = MarkdownSectionMerge.merge(variants: [base, contribution])
        #expect(merged == "## S\n- a\n- b\n\nBase paragraph.\n\nContribution paragraph.\n")
    }

    @Test("Contribution prose matching no heading lands at the document end, deduplicated")
    func unmatchedProseAppendsAtEnd() {
        let merged = MarkdownSectionMerge.merge(variants: ["intro\n\n## S\n- a\n", "intro\nmore\n\n## S\n- b\n"])
        #expect(merged == "intro\n\n## S\n- a\n- b\n\nmore\n")
    }

    @Test("An empty base section takes the contribution body wholesale")
    func emptyBaseSectionFilled() {
        let merged = MarkdownSectionMerge.merge(variants: ["## S\n\n## T\n- t\n", "## S\n- s\n"])
        #expect(merged == "## S\n- s\n\n## T\n- t\n")
    }

    @Test("droppingEmptySections removes headings without content")
    func dropEmptySections() {
        let text = "# Title\n\n## Empty\n\n## Full\n- x\n\n## AlsoEmpty\n"
        #expect(MarkdownSectionMerge.droppingEmptySections(text) == "# Title\n\n## Full\n- x\n")
    }

    @Test("A variant without any shared heading appends at the bottom")
    func disjointAppendsAtBottom() {
        #expect(MarkdownSectionMerge.merge(variants: ["BASE-T", "MAC-T"]) == "BASE-T\n\nMAC-T")
        #expect(
            MarkdownSectionMerge.merge(variants: ["BASE-T\n", "MAC-T\n"]) == "BASE-T\n\nMAC-T\n")
    }

    @Test("YAML frontmatter takes the later variant wholesale; the body still merges")
    func frontmatterLaterWins() {
        let base = "---\nname: base\n---\n# Agent\n\n## Rules\n- a\n"
        let contribution = "---\nname: specific\n---\n## Rules\n- b\n"
        let merged = MarkdownSectionMerge.merge(variants: [base, contribution])
        #expect(merged == "---\nname: specific\n---\n# Agent\n\n## Rules\n- a\n- b\n")
    }

    @Test("Heading matching is exact per level: ## A and ### A stay distinct")
    func headingLevelDistinct() {
        let merged = MarkdownSectionMerge.merge(variants: ["## A\n- a\n", "### A\n- sub\n"])
        #expect(merged == "## A\n- a\n\n### A\n- sub\n")
    }

    @Test("A '#' line inside a fenced code block is not a section heading")
    func fenceInternalHashIsNotHeading() {
        let base = "## Build\n```bash\n# release\nswift build\n```\n"
        let contribution = "## Deploy\n- ship\n"
        let merged = MarkdownSectionMerge.merge(variants: [base, contribution])
        #expect(merged == "## Build\n```bash\n# release\nswift build\n```\n\n## Deploy\n- ship\n")
    }

    @Test("A contribution's fenced block keeps its delimiters even when the base has a fence")
    func fenceDelimitersSurviveDedup() {
        let base = "## S\n```\nmake build\n```\n"
        let contribution = "## S\n```\nmake test\n```\n"
        let merged = MarkdownSectionMerge.merge(variants: [base, contribution])
        #expect(merged == "## S\n```\nmake build\n```\n```\nmake test\n```\n")
    }

    @Test("Merging an identical fenced block twice stays a no-op, blank lines included")
    func identicalFenceNoOp() {
        let doc = "## S\n```bash\nswift build\n\nswift test\n```\n"
        #expect(MarkdownSectionMerge.merge(variants: [doc, doc]) == doc)
    }

    @Test("droppingEmptySections keeps a parent heading whose content lives in a subheading")
    func dropEmptySectionsKeepsParentOfFullChild() {
        let text = "# Title\n\n## Docs\n### API\n- endpoints\n\n## Empty\n### AlsoEmpty\n"
        #expect(
            MarkdownSectionMerge.droppingEmptySections(text)
                == "# Title\n\n## Docs\n\n### API\n- endpoints\n")
    }
}
