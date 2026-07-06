import Testing

@testable import Plumage

@Suite("GitTagModel validation")
struct GitTagModelTests {
    @Test("an empty or whitespace-only name is rejected")
    func emptyRejected() {
        #expect(GitTagModel.tagNameError("", existing: []) != nil)
        #expect(GitTagModel.tagNameError("   ", existing: []) != nil)
    }

    @Test("an unsafe name (space, leading dash, dot-dot) is rejected")
    func unsafeRejected() {
        #expect(GitTagModel.tagNameError("bad name", existing: []) != nil)
        #expect(GitTagModel.tagNameError("-x", existing: []) != nil)
        #expect(GitTagModel.tagNameError("a..b", existing: []) != nil)
    }

    @Test("a name matching an existing tag is rejected")
    func duplicateRejected() {
        #expect(GitTagModel.tagNameError("v1.0.0", existing: ["v1.0.0"]) != nil)
    }

    @Test("a valid, unique name passes")
    func validPasses() {
        #expect(GitTagModel.tagNameError("v1.0.0", existing: ["v0.9.0"]) == nil)
    }

    @Test("surrounding whitespace is trimmed before the duplicate check")
    func trimsBeforeDuplicateCheck() {
        #expect(GitTagModel.tagNameError("  v1.0.0  ", existing: ["v1.0.0"]) != nil)
    }
}
