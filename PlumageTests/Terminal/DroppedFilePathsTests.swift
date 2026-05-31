import Foundation
import Testing

@testable import Plumage

@Suite("DroppedFilePaths")
struct DroppedFilePathsTests {
    @Test("single path is single-quoted with a trailing space")
    func singlePath() {
        let url = URL(fileURLWithPath: "/Users/me/notes.txt")
        #expect(DroppedFilePaths.insertionText(for: [url]) == "'/Users/me/notes.txt' ")
    }

    @Test("multiple paths are space-joined, each quoted, one trailing space")
    func multiplePaths() {
        let urls = [
            URL(fileURLWithPath: "/a/one.txt"),
            URL(fileURLWithPath: "/b/two.png"),
        ]
        #expect(DroppedFilePaths.insertionText(for: urls) == "'/a/one.txt' '/b/two.png' ")
    }

    @Test("path with spaces stays inside one quoted token")
    func pathWithSpaces() {
        let url = URL(fileURLWithPath: "/Users/me/My Project/main file.swift")
        #expect(
            DroppedFilePaths.insertionText(for: [url])
                == "'/Users/me/My Project/main file.swift' "
        )
    }

    @Test("single quote in path is POSIX-escaped")
    func pathWithSingleQuote() {
        let url = URL(fileURLWithPath: "/Users/me/it's mine.txt")
        #expect(
            DroppedFilePaths.insertionText(for: [url])
                == #"'/Users/me/it'\''s mine.txt' "#
        )
    }

    @Test("empty input yields an empty string, no stray space")
    func emptyInput() {
        #expect(DroppedFilePaths.insertionText(for: []).isEmpty)
    }
}
