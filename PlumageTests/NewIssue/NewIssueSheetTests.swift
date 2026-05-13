import Foundation
import Testing

@testable import Plumage

@Suite("NewIssueInput")
@MainActor
struct NewIssueSheetTests {
    @Test("Slug auto-derives from title until first manual slug edit, then sticks")
    func slugAutoDeriveSticky() {
        let input = NewIssueInput()
        input.title = "Add Labels"
        input.handleTitleChanged()
        #expect(input.slug == "add-labels")

        input.title = "Add Labels Support"
        input.handleTitleChanged()
        #expect(input.slug == "add-labels-support")

        input.slug = "custom-slug"
        input.slugTouched = true
        #expect(input.slug == "custom-slug")
        #expect(input.slugTouched)

        input.title = "Add Labels Support v2"
        input.handleTitleChanged()
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
            input.slug = slug
            input.slugTouched = true
            #expect(input.slugValid == expected, "slug=\(slug)")
        }
    }

    @Test("Submit is disabled with empty title, enabled when title and slug are valid")
    func submitEnabledMatrix() {
        let input = NewIssueInput()
        #expect(!input.submitEnabled(existingIssues: []))

        input.title = "X"
        input.handleTitleChanged()
        #expect(input.submitEnabled(existingIssues: []))

        input.slug = "Invalid Slug"
        input.slugTouched = true
        #expect(!input.submitEnabled(existingIssues: []))

        input.slug = "valid-slug"
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
        input.title = "Foo"
        input.handleTitleChanged()
        input.slug = "foo"
        input.slugTouched = true
        #expect(input.collidingFolder(in: existing) == "00003-foo")
        #expect(!input.submitEnabled(existingIssues: existing))

        input.slug = "bar"
        #expect(input.collidingFolder(in: existing) == nil)
        #expect(input.submitEnabled(existingIssues: existing))
    }
}
