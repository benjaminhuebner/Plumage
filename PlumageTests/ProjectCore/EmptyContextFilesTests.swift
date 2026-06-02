import Testing

@testable import Plumage

struct EmptyContextFilesTests {
    @Test
    func emptyStringIsEmpty() {
        #expect(EmptyContextFiles.isEffectivelyEmpty(""))
    }

    @Test
    func whitespaceOnlyIsEmpty() {
        #expect(EmptyContextFiles.isEffectivelyEmpty("\n"))
        #expect(EmptyContextFiles.isEffectivelyEmpty(" "))
        #expect(EmptyContextFiles.isEffectivelyEmpty("  \t\n  \r\n  "))
    }

    @Test
    func realContentIsNotEmpty() {
        #expect(!EmptyContextFiles.isEffectivelyEmpty("# Title"))
        #expect(!EmptyContextFiles.isEffectivelyEmpty("\n\n  x  \n"))
    }

    @Test
    func targetSetMatchesExactRelativePaths() {
        #expect(EmptyContextFiles.isTarget(relativePath: ".claude/CLAUDE.md"))
        #expect(EmptyContextFiles.isTarget(relativePath: "CLAUDE.md"))
        #expect(EmptyContextFiles.isTarget(relativePath: ".claude/docs/PROJECT.md"))
        // Non-targets: stray same-named files and the other docs never warn.
        #expect(!EmptyContextFiles.isTarget(relativePath: "PROJECT.md"))
        #expect(!EmptyContextFiles.isTarget(relativePath: ".claude/docs/notes.md"))
        #expect(!EmptyContextFiles.isTarget(relativePath: ".claude/docs/decisions.md"))
    }
}
