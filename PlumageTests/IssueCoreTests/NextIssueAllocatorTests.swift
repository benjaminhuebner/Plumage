import Foundation
import Testing

@testable import Plumage

@Suite("NextIssueAllocator pure helpers")
struct NextIssueAllocatorPureTests {
    @Test(
        "slugify lowercases, replaces non-alnum with hyphen, collapses, trims",
        arguments: [
            ("Add Labels Support", "add-labels-support"),
            ("Über—User_Auth", "ber-user-auth"),
            ("---foo bar---", "foo-bar"),
            ("", ""),
            ("Already-kebab-case", "already-kebab-case"),
            ("UPPER", "upper"),
            ("a b   c", "a-b-c"),
            ("123 Numbers", "123-numbers"),
        ]
    )
    func slugifyCases(input: String, expected: String) {
        #expect(NextIssueAllocator.slugify(input) == expected)
    }

    @Test(
        "paddedID zero-pads up to width and grows beyond",
        arguments: [
            (7, 5, "00007"),
            (100_000, 5, "100000"),
            (1, 3, "001"),
        ]
    )
    func paddedIDCases(id: Int, padding: Int, expected: String) {
        #expect(NextIssueAllocator.paddedID(id, padding: padding) == expected)
    }

    @Test(
        "isValidSlug accepts kebab and rejects everything else",
        arguments: [
            ("foo", true),
            ("foo-bar", true),
            ("a", true),
            ("00007-foo", true),
            ("1foo", true),
            ("", false),
            ("-foo", false),
            ("Foo", false),
            ("foo_bar", false),
            ("foo bar", false),
        ]
    )
    func slugValidationCases(input: String, expected: Bool) {
        #expect(NextIssueAllocator.isValidSlug(input) == expected)
    }

    @Test("substituteTemplate replaces all markers and injects type and labels")
    func substituteTemplateFull() {
        let template = """
            ---
            id: <<<ID>>>
            title: <<<TITLE>>>
            type: feature
            status: draft
            created: <<<CREATED>>>
            updated: <<<CREATED>>>
            branch: issue/<<<ID_PADDED>>>-<<<SLUG>>>
            labels: []
            model: null
            ---

            # Issue <<<ID_PADDED>>>: <<<TITLE>>>
            """

        let rendered = NextIssueAllocator.substituteTemplate(
            template,
            id: 2,
            idPadded: "00002",
            title: "Bar",
            slug: "bar",
            created: "2026-05-13T07:00:00Z",
            type: .chore,
            labels: ["chore", "v0.1"]
        )

        #expect(rendered.contains("id: 2\n"))
        #expect(rendered.contains("title: Bar\n"))
        #expect(rendered.contains("type: chore\n"))
        #expect(rendered.contains("labels: [chore, v0.1]\n"))
        #expect(rendered.contains("branch: issue/00002-bar\n"))
        #expect(rendered.contains("created: 2026-05-13T07:00:00Z\n"))
        #expect(rendered.contains("# Issue 00002: Bar"))
        #expect(!rendered.contains("<<<"))
    }

    @Test("substituteTemplate keeps feature type when type is .feature and empty labels stay empty")
    func substituteTemplateDefaults() {
        let template = """
            type: feature
            labels: []
            """
        let rendered = NextIssueAllocator.substituteTemplate(
            template,
            id: 1,
            idPadded: "00001",
            title: "T",
            slug: "t",
            created: "x",
            type: .feature,
            labels: []
        )
        #expect(rendered.contains("type: feature"))
        #expect(rendered.contains("labels: []"))
    }
}
