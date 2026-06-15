import Testing

@testable import Plumage

@Suite("LabelChipEditor")
struct LabelChipEditorTests {
    @Test("rejects empty and whitespace-only input")
    func rejectsEmpty() {
        #expect(!LabelChipEditor.isValid(""))
        #expect(!LabelChipEditor.isValid("   "))
        #expect(!LabelChipEditor.isValid("\t"))
    }

    @Test("rejects commas, brackets, and inner whitespace")
    func rejectsInvalidChars() {
        #expect(!LabelChipEditor.isValid("a,b"))
        #expect(!LabelChipEditor.isValid("a[b"))
        #expect(!LabelChipEditor.isValid("a]b"))
        #expect(!LabelChipEditor.isValid("a b"))
    }

    @Test("accepts ASCII labels and labels with dashes / digits / dots")
    func acceptsValid() {
        #expect(LabelChipEditor.isValid("feature"))
        #expect(LabelChipEditor.isValid("v0.1"))
        #expect(LabelChipEditor.isValid("ui-polish"))
        #expect(LabelChipEditor.isValid("00001"))
    }

    @Test("trims leading/trailing whitespace before validating")
    func trimsBeforeValidating() {
        #expect(LabelChipEditor.isValid("  feature  "))
        #expect(!LabelChipEditor.isValid("  a b  "))
    }

    @Test("suggestion filter: empty draft yields no matches")
    func emptyDraftYieldsNoMatches() {
        #expect(LabelChipEditor.matches(for: "", in: ["kanban", "ui"]).isEmpty)
        #expect(LabelChipEditor.matches(for: "   ", in: ["kanban", "ui"]).isEmpty)
    }

    @Test("suggestion filter: case-insensitive prefix match")
    func prefixMatchIsCaseInsensitive() {
        #expect(LabelChipEditor.matches(for: "KA", in: ["kanban", "ui", "kotlin"]) == ["kanban"])
        #expect(
            LabelChipEditor.matches(for: "k", in: ["kanban", "ui", "Kotlin"]) == ["kanban", "Kotlin"])
    }

    @Test("suggestion filter: a non-prefix substring does not match")
    func substringThatIsNotAPrefixDoesNotMatch() {
        #expect(LabelChipEditor.matches(for: "anban", in: ["kanban"]).isEmpty)
    }

    @Test("suggestion filter: an unmatched needle yields empty")
    func unmatchedNeedleYieldsEmpty() {
        #expect(LabelChipEditor.matches(for: "zzz", in: ["kanban", "ui"]).isEmpty)
    }

    @Test("accept: substitutes an exact existing label, normalizing casing")
    func acceptSubstitutesExactExistingLabel() {
        #expect(
            LabelChipEditor.acceptedLabel(
                draft: "Kanban", existingLabels: ["kanban"], currentLabels: []) == "kanban")
    }

    @Test("accept: a prefix of an existing label stays creatable as typed")
    func acceptCreatesPrefixOfExistingLabel() {
        #expect(
            LabelChipEditor.acceptedLabel(draft: "ka", existingLabels: ["kanban"], currentLabels: [])
                == "ka")
    }

    @Test("accept: falls back to a valid free-typed label when nothing matches")
    func acceptFallsBackToValidTypedLabel() {
        #expect(
            LabelChipEditor.acceptedLabel(
                draft: "brand-new", existingLabels: ["kanban"], currentLabels: []) == "brand-new")
    }

    @Test("accept: rejects an invalid free-typed label")
    func acceptRejectsInvalidTypedLabel() {
        #expect(
            LabelChipEditor.acceptedLabel(draft: "has space", existingLabels: [], currentLabels: [])
                == nil)
        #expect(LabelChipEditor.acceptedLabel(draft: "", existingLabels: [], currentLabels: []) == nil)
    }

    @Test("accept: rejects a typed label already on the issue")
    func acceptRejectsTypedLabelAlreadyOnIssue() {
        #expect(
            LabelChipEditor.acceptedLabel(draft: "ui", existingLabels: [], currentLabels: ["ui"])
                == nil)
    }
}
