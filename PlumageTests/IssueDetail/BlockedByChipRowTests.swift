import Foundation
import Testing

@testable import Plumage

@Suite("BlockedByChipRow.matches")
struct BlockedByChipRowTests {
    private let candidates = [
        BlockerCandidate(folderName: "00042-auth", id: 42, title: "User auth"),
        BlockerCandidate(folderName: "00043-board", id: 43, title: "Board polish"),
        BlockerCandidate(folderName: "00100-editor", id: 100, title: "Editor tabs"),
    ]

    @Test("matches by id fragment")
    func idFragment() {
        let matches = BlockedByChipRow.matches(for: "42", in: candidates, excluding: [])
        #expect(matches.map(\.folderName) == ["00042-auth"])
    }

    @Test("matches with leading hash")
    func hashPrefix() {
        let matches = BlockedByChipRow.matches(for: "#00043", in: candidates, excluding: [])
        #expect(matches.map(\.folderName) == ["00043-board"])
    }

    @Test("matches by title substring, case-insensitive")
    func titleSubstring() {
        let matches = BlockedByChipRow.matches(for: "BOARD", in: candidates, excluding: [])
        #expect(matches.map(\.folderName) == ["00043-board"])
    }

    @Test("already-added blockers are excluded")
    func excludesCurrent() {
        let matches = BlockedByChipRow.matches(
            for: "auth", in: candidates, excluding: ["00042-auth"])
        #expect(matches.isEmpty)
    }

    @Test("empty draft yields no matches")
    func emptyDraft() {
        #expect(BlockedByChipRow.matches(for: "  ", in: candidates, excluding: []).isEmpty)
    }

    @Test("matches cap at eight")
    func capAtEight() {
        let many = (1...20).map {
            BlockerCandidate(folderName: "000\($0)-x", id: $0, title: "Shared title")
        }
        let matches = BlockedByChipRow.matches(for: "shared", in: many, excluding: [])
        #expect(matches.count == 8)
    }
}
