import Foundation
import Testing

@testable import Plumage

@Suite("DroppedFilePaths")
struct DroppedFilePathsTests {
    @Test("whitespace-free path is inserted bare with a trailing space")
    func singlePath() {
        let url = URL(fileURLWithPath: "/Users/me/notes.txt")
        #expect(DroppedFilePaths.insertionText(for: [url]) == "/Users/me/notes.txt ")
    }

    @Test("multiple paths are space-joined, one trailing space")
    func multiplePaths() {
        let urls = [
            URL(fileURLWithPath: "/a/one.txt"),
            URL(fileURLWithPath: "/b/two.png"),
        ]
        #expect(DroppedFilePaths.insertionText(for: urls) == "/a/one.txt /b/two.png ")
    }

    @Test("path with spaces is double-quoted so it stays one token")
    func pathWithSpaces() {
        let url = URL(fileURLWithPath: "/Users/me/My Project/main file.swift")
        #expect(
            DroppedFilePaths.insertionText(for: [url])
                == "\"/Users/me/My Project/main file.swift\" "
        )
    }

    @Test("apostrophe in a whitespace-free path stays literal, unquoted")
    func pathWithApostropheNoSpace() {
        let url = URL(fileURLWithPath: "/Users/me/it's.txt")
        #expect(DroppedFilePaths.insertionText(for: [url]) == "/Users/me/it's.txt ")
    }

    @Test("apostrophe inside a spaced path stays literal within the double quotes")
    func pathWithApostropheAndSpace() {
        let url = URL(fileURLWithPath: "/Users/me/it's mine.txt")
        #expect(
            DroppedFilePaths.insertionText(for: [url])
                == "\"/Users/me/it's mine.txt\" "
        )
    }

    @Test("empty input yields an empty string, no stray space")
    func emptyInput() {
        #expect(DroppedFilePaths.insertionText(for: []).isEmpty)
    }
}
