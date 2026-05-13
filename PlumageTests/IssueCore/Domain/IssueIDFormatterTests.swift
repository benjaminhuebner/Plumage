import Testing

@testable import Plumage

@Suite("IssueIDFormatter")
struct IssueIDFormatterTests {
    @Test("padded uses width as zero-padding")
    func paddedDefaultWidth() {
        #expect(IssueIDFormatter.padded(7, width: 5) == "00007")
        #expect(IssueIDFormatter.padded(42, width: 5) == "00042")
        #expect(IssueIDFormatter.padded(12345, width: 5) == "12345")
    }

    @Test("padded does not truncate ids wider than the width")
    func paddedWiderThanWidth() {
        #expect(IssueIDFormatter.padded(123456, width: 5) == "123456")
    }

    @Test("padded with width 0 falls back to width 1")
    func paddedWidthZero() {
        #expect(IssueIDFormatter.padded(0, width: 0) == "0")
        #expect(IssueIDFormatter.padded(9, width: 0) == "9")
    }

    @Test("padded with negative width falls back to width 1")
    func paddedNegativeWidth() {
        #expect(IssueIDFormatter.padded(3, width: -1) == "3")
    }

    @Test("paddedOrPlaceholder formats present id")
    func placeholderWithId() {
        #expect(IssueIDFormatter.paddedOrPlaceholder(7, width: 5) == "00007")
    }

    @Test("paddedOrPlaceholder uses question marks when id is nil")
    func placeholderNil() {
        #expect(IssueIDFormatter.paddedOrPlaceholder(nil, width: 5) == "?????")
        #expect(IssueIDFormatter.paddedOrPlaceholder(nil, width: 1) == "?")
    }

    @Test("paddedOrPlaceholder with nil and width <= 0 returns single question mark")
    func placeholderNilZeroWidth() {
        #expect(IssueIDFormatter.paddedOrPlaceholder(nil, width: 0) == "?")
        #expect(IssueIDFormatter.paddedOrPlaceholder(nil, width: -3) == "?")
    }
}
