import Foundation
import Testing

@testable import Plumage

@Suite("IssueFilter")
struct IssueFilterTests {
    private let issue = DiscoveredIssue.valid(
        Plumage.Issue(
            id: 42, folderName: "00042-uber-board", title: "Über-Board polish",
            type: .feature, status: .approved,
            created: .distantPast, updated: .distantPast,
            branch: "issue/00042-uber-board", labels: ["ui", "v0.1"]
        )
    )
    private let invalid = DiscoveredIssue.invalid(
        folder: URL(filePath: "/tmp/issues/00007-broken-spec"),
        error: .missingFrontmatter
    )

    @Test("empty filter is inactive and matches everything")
    func emptyMatchesAll() {
        let filter = IssueFilter()
        #expect(!filter.isActive)
        #expect(filter.matches(issue))
        #expect(filter.matches(invalid))
    }

    @Test("whitespace-only text stays inactive")
    func whitespaceInactive() {
        let filter = IssueFilter(text: "   ")
        #expect(!filter.isActive)
        #expect(filter.matches(issue))
    }

    @Test(
        "text matches title case- and diacritic-insensitively",
        arguments: ["uber", "ÜBER", "board", "polish"]
    )
    func titleText(needle: String) {
        let filter = IssueFilter(text: needle)
        #expect(filter.isActive)
        #expect(filter.matches(issue))
    }

    @Test("text matches the padded id, with or without hash", arguments: ["42", "#42", "00042"])
    func idText(needle: String) {
        #expect(IssueFilter(text: needle).matches(issue))
    }

    @Test("text matches labels")
    func labelText() {
        #expect(IssueFilter(text: "v0.1").matches(issue))
        #expect(!IssueFilter(text: "backend").matches(issue))
    }

    @Test("label multi-select requires every selected label")
    func labelFacetAnd() {
        #expect(IssueFilter(selectedLabels: ["ui"]).matches(issue))
        #expect(IssueFilter(selectedLabels: ["ui", "v0.1"]).matches(issue))
        #expect(!IssueFilter(selectedLabels: ["ui", "backend"]).matches(issue))
    }

    @Test("type facet matches exactly")
    func typeFacet() {
        #expect(IssueFilter(type: .feature).matches(issue))
        #expect(!IssueFilter(type: .chore).matches(issue))
    }

    @Test("facets and text combine as AND")
    func combined() {
        let matching = IssueFilter(text: "über", selectedLabels: ["ui"], type: .feature)
        #expect(matching.matches(issue))
        let wrongText = IssueFilter(text: "nope", selectedLabels: ["ui"], type: .feature)
        #expect(!wrongText.matches(issue))
    }

    @Test("invalid card matches text via folder name only")
    func invalidTextViaFolder() {
        #expect(IssueFilter(text: "broken").matches(invalid))
        #expect(IssueFilter(text: "00007").matches(invalid))
        #expect(!IssueFilter(text: "elsewhere").matches(invalid))
    }

    @Test("invalid card never matches label or type facets")
    func invalidExcludedFromFacets() {
        #expect(!IssueFilter(selectedLabels: ["ui"]).matches(invalid))
        #expect(!IssueFilter(type: .feature).matches(invalid))
        #expect(!IssueFilter(text: "broken", type: .feature).matches(invalid))
    }
}
