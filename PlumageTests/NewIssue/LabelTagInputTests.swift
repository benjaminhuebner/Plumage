import Foundation
import Testing

@testable import Plumage

@Suite("LabelTagInputLogic")
struct LabelTagInputTests {
    @Test("Enter on submit commits draft and clears it")
    func enterCommits() {
        var labels: [String] = []
        var draft = "feature"
        LabelTagInputLogic.commit(draft: &draft, into: &labels)
        #expect(labels == ["feature"])
        #expect(draft.isEmpty)
    }

    @Test("Comma in draft commits the preceding text and keeps the trailing portion as the new draft")
    func commaCommits() {
        var labels: [String] = []
        var draft = ""
        LabelTagInputLogic.handleDraftChange(new: "feature,", draft: &draft, labels: &labels)
        #expect(labels == ["feature"])
        #expect(draft.isEmpty)

        LabelTagInputLogic.handleDraftChange(new: "v0.1,boot", draft: &draft, labels: &labels)
        #expect(labels == ["feature", "v0.1"])
        #expect(draft == "boot")
    }

    @Test("Duplicate insertion is ignored")
    func dedup() {
        var labels: [String] = ["feature"]
        var draft = "feature"
        LabelTagInputLogic.commit(draft: &draft, into: &labels)
        #expect(labels == ["feature"])
    }

    @Test("Backspace on empty draft removes the last label")
    func backspaceRemovesLast() {
        var labels: [String] = ["feature", "v0.1"]
        LabelTagInputLogic.handleBackspaceOnEmptyDraft(draft: "", labels: &labels)
        #expect(labels == ["feature"])
    }

    @Test("Backspace with non-empty draft is a no-op")
    func backspaceNonEmptyDraftNoop() {
        var labels: [String] = ["feature"]
        LabelTagInputLogic.handleBackspaceOnEmptyDraft(draft: "x", labels: &labels)
        #expect(labels == ["feature"])
    }

    @Test("Whitespace is trimmed before commit")
    func whitespaceTrim() {
        var labels: [String] = []
        var draft = "  feat  "
        LabelTagInputLogic.commit(draft: &draft, into: &labels)
        #expect(labels == ["feat"])
    }

    @Test("Empty or whitespace-only token is ignored")
    func emptyTokenIgnored() {
        var labels: [String] = []
        var draft = "  "
        LabelTagInputLogic.commit(draft: &draft, into: &labels)
        #expect(labels.isEmpty)

        LabelTagInputLogic.handleDraftChange(new: ",", draft: &draft, labels: &labels)
        #expect(labels.isEmpty)
    }
}
