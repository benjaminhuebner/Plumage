import Foundation
import Testing

@testable import Plumage

@Suite("NewIssueInput")
@MainActor
struct NewIssueSheetTests {
    @Test("Slug auto-derives from title until first manual slug edit, then sticks")
    func slugAutoDeriveSticky() {
        let input = NewIssueInput()
        input.onTitleChange("Add Labels")
        #expect(input.slug == "add-labels")

        input.onTitleChange("Add Labels Support")
        #expect(input.slug == "add-labels-support")

        input.onSlugEdit("custom-slug")
        #expect(input.slug == "custom-slug")
        #expect(input.slugTouched)

        input.onTitleChange("Add Labels Support v2")
        #expect(input.slug == "custom-slug")
    }

    @Test("slugValid is correct for kebab cases and rejects empty/leading-hyphen/upper/underscore/space")
    func regexValidation() {
        let cases: [(String, Bool)] = [
            ("foo", true),
            ("foo-bar", true),
            ("a", true),
            ("00001-foo", true),
            ("1foo", true),
            ("", false),
            ("-foo", false),
            ("Foo", false),
        ]
        for (slug, expected) in cases {
            let input = NewIssueInput()
            input.onSlugEdit(slug)
            #expect(input.slugValid == expected, "slug=\(slug)")
        }
    }

    @Test("Submit is disabled with empty title, enabled when title and slug are valid")
    func submitEnabledMatrix() {
        let input = NewIssueInput()
        #expect(!input.submitEnabled(existingIssues: []))

        input.onTitleChange("X")
        #expect(input.submitEnabled(existingIssues: []))

        input.onSlugEdit("Invalid Slug")
        #expect(!input.submitEnabled(existingIssues: []))

        input.onSlugEdit("valid-slug")
        #expect(input.submitEnabled(existingIssues: []))
    }

    @Test("Collision detection finds matching folder in existingIssues")
    func collisionPreCheck() {
        let existing: [DiscoveredIssue] = [
            .valid(
                Plumage.Issue(
                    id: 3,
                    folderName: "00003-foo",
                    title: "Foo",
                    type: .feature,
                    status: .approved,
                    created: .distantPast,
                    updated: .distantPast,
                    branch: "issue/00003-foo",
                    labels: [],
                    model: nil
                )
            )
        ]
        let input = NewIssueInput()
        input.onTitleChange("Foo")
        input.onSlugEdit("foo")
        #expect(input.collidingFolder(in: existing) == "00003-foo")
        #expect(!input.submitEnabled(existingIssues: existing))

        input.onSlugEdit("bar")
        #expect(input.collidingFolder(in: existing) == nil)
        #expect(input.submitEnabled(existingIssues: existing))
    }
}
