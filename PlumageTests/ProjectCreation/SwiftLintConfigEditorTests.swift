import Testing

@testable import Plumage

@Suite("SwiftLintConfigEditor")
struct SwiftLintConfigEditorTests {
    @Test("appends under an existing excluded block, after the last entry")
    func appendsToExistingBlock() {
        let yaml = "excluded:\n  - .build\n  - DerivedData\n"
        #expect(
            SwiftLintConfigEditor.addingExclude("Plumage.plumage", to: yaml)
                == "excluded:\n  - .build\n  - DerivedData\n  - Plumage.plumage\n")
    }

    @Test("is a no-op when the entry is already listed")
    func dedupesExistingEntry() {
        let yaml = "excluded:\n  - .build\n  - Plumage.plumage\n"
        #expect(SwiftLintConfigEditor.addingExclude("Plumage.plumage", to: yaml) == yaml)
    }

    @Test("creates the excluded key when absent")
    func createsKeyWhenAbsent() {
        let yaml = "only_rules:\n  - foo\n"
        #expect(
            SwiftLintConfigEditor.addingExclude("Plumage.plumage", to: yaml)
                == "only_rules:\n  - foo\n\nexcluded:\n  - Plumage.plumage\n")
    }

    @Test("creates the excluded section from empty input")
    func createsSectionFromEmpty() {
        #expect(
            SwiftLintConfigEditor.addingExclude("Plumage.plumage", to: "")
                == "excluded:\n  - Plumage.plumage\n")
    }

    @Test("adds the first item under an empty excluded key")
    func addsFirstItemUnderEmptyKey() {
        #expect(
            SwiftLintConfigEditor.addingExclude("Plumage.plumage", to: "excluded:\n")
                == "excluded:\n  - Plumage.plumage\n")
    }

    @Test("an empty or whitespace entry is a no-op")
    func emptyEntryIsNoOp() {
        let yaml = "excluded:\n  - .build\n"
        #expect(SwiftLintConfigEditor.addingExclude("", to: yaml) == yaml)
        #expect(SwiftLintConfigEditor.addingExclude("   ", to: yaml) == yaml)
    }

    @Test("applying twice equals applying once")
    func isIdempotent() {
        let yaml = "excluded:\n  - .build\n"
        let once = SwiftLintConfigEditor.addingExclude("x.plumage", to: yaml)
        let twice = SwiftLintConfigEditor.addingExclude("x.plumage", to: once)
        #expect(once == twice)
    }

    @Test("inserts after the last entry, leaving trailing config untouched")
    func insertsBeforeTrailingConfig() {
        let yaml =
            "excluded:\n  - .build\n  - DerivedData\n  - .swiftpm\n\n# config\nidentifier_name:\n  min_length: 2\n"
        #expect(
            SwiftLintConfigEditor.addingExclude("Plumage.plumage", to: yaml)
                == "excluded:\n  - .build\n  - DerivedData\n  - .swiftpm\n  - Plumage.plumage\n\n# config\nidentifier_name:\n  min_length: 2\n"
        )
    }
}
