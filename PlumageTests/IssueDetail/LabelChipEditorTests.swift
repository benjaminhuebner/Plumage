import Testing

@testable import Plumage

@Suite("LabelChipEditor.isValid")
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
}
